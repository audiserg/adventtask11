// Стратегия загрузки сообщений из LTM

// Конфигурация лимитов контекстных окон для всех моделей (в токенах)
const MODEL_CONTEXT_LIMITS = {
  // DeepSeek модели
  'deepseek-chat': 64000,
  'deepseek-reasoner': 64000,
  'deepseek-chat-reasoner': 64000,
  'deepseek-ai/DeepSeek-V3-0324': 128000,
  'deepseek-ai/DeepSeek-V2-Lite': 64000,
  'deepseek-ai/DeepSeek-R1': 64000,
  
  // Qwen модели
  'Qwen/Qwen2.5-72B-Instruct': 128000,
  'Qwen/Qwen2.5-32B-Instruct': 128000,
  'Qwen/Qwen2.5-14B-Instruct': 128000,
  'Qwen/Qwen2.5-7B-Instruct': 128000,
  'Qwen/Qwen2.5-3B-Instruct': 128000,
  
  // Llama модели
  'meta-llama/Llama-3.1-8B-Instruct': 128000,
  'meta-llama/Llama-3.1-70B-Instruct': 128000,
  'meta-llama/Llama-3.2-3B-Instruct': 128000,
  'meta-llama/Llama-2-7b-chat-hf': 4096,
  
  // Gemma модели
  'google/gemma-2-2b-it': 8192,
  'google/gemma-2-9b-it': 8192,
  
  // Mistral модели
  'mistralai/Mistral-7B-Instruct-v0.2': 32768,
  'mistralai/Mixtral-8x7B-Instruct-v0.1': 32768,
  
  // GLM модели
  'zai-org/GLM-4.7-Flash:novita': 128000,
};

// Функция для получения лимита контекстного окна модели
function getModelContextLimit(model) {
  if (!model) {
    return 64000; // Значение по умолчанию
  }
  
  // Прямое совпадение
  if (MODEL_CONTEXT_LIMITS[model]) {
    return MODEL_CONTEXT_LIMITS[model];
  }
  
  // Поиск по частичному совпадению (для моделей с версиями)
  for (const [key, value] of Object.entries(MODEL_CONTEXT_LIMITS)) {
    if (model.includes(key) || key.includes(model)) {
      return value;
    }
  }
  
  // Значения по умолчанию в зависимости от провайдера
  if (model.includes('deepseek')) {
    return 64000;
  }
  if (model.includes('qwen') || model.includes('Qwen')) {
    return 128000;
  }
  if (model.includes('llama') || model.includes('Llama')) {
    return 128000;
  }
  if (model.includes('gemma') || model.includes('Gemma')) {
    return 8192;
  }
  if (model.includes('mistral') || model.includes('Mistral')) {
    return 32768;
  }
  
  // Значение по умолчанию
  return 64000;
}

export class LTMStrategy {
  // Семантический поиск через LLM: загружаем пачку сообщений и используем LLM для определения релевантности
  static async searchLTM(db, model, userQuery, offsetTokens = 0, provider, sendToProviderFn, temperature = 0.7) {
    // Получаем лимит контекста модели
    const maxContextTokens = getModelContextLimit(model);
    // Используем часть лимита для загрузки сообщений (примерно 1.5 лимита для пачки)
    const availableTokens = Math.floor(maxContextTokens * 1.5);
    
    // Загружаем пачку сообщений из LTM (без текстового поиска, просто по токенам)
    const batchResult = await db.getLTMessagesByTokens(availableTokens, offsetTokens);
    
    if (!batchResult.success || batchResult.messages.length === 0) {
      return {
        messages: [],
        totalTokens: offsetTokens,
        hasMore: false,
        relevantMessages: []
      };
    }
    
    const batchMessages = batchResult.messages;
    console.log(`📦 Loaded ${batchMessages.length} messages from LTM (offset: ${offsetTokens} tokens) for semantic search`);
    
    // Формируем промпт для LLM для определения релевантных сообщений
    // Показываем полный текст сообщений для лучшего понимания контекста
    const messagesList = batchMessages.map((msg, idx) => {
      // Показываем полный текст, но ограничиваем очень длинные сообщения
      const content = msg.content.length > 500 
        ? msg.content.substring(0, 500) + '...'
        : msg.content;
      return `[${idx}] ${msg.role === 'user' ? 'Пользователь' : 'Ассистент'}: ${content}`;
    }).join('\n\n---\n\n');
    
    const semanticSearchPrompt = `Ты помогаешь найти релевантные сообщения из истории разговора для ответа на вопрос пользователя.

ВОПРОС ПОЛЬЗОВАТЕЛЯ: "${userQuery}"

НИЖЕ ПРИВЕДЕНЫ СООБЩЕНИЯ ИЗ ИСТОРИИ (пронумерованы от 0 до ${batchMessages.length - 1}):

${messagesList}

ЗАДАЧА: Проанализируй каждое сообщение и определи, какие из них содержат информацию, релевантную для ответа на вопрос пользователя "${userQuery}".

КРИТЕРИИ РЕЛЕВАНТНОСТИ:
- Сообщение содержит информацию, которая напрямую отвечает на вопрос
- Сообщение содержит контекст, необходимый для понимания вопроса
- Сообщение содержит связанную информацию, которая поможет дать полный ответ

ФОРМАТ ОТВЕТА: Верни ТОЛЬКО список номеров релевантных сообщений в формате: [0, 3, 5, 7]
Если релевантных сообщений нет, верни: []

ВАЖНО: Не добавляй никаких объяснений, только список номеров в квадратных скобках.`;
    
    // Делаем микрозапрос к LLM для определения релевантности
    const microRequestMessages = [
      {
        role: 'system',
        content: 'Ты помощник для поиска релевантных сообщений. Отвечай только списком номеров в формате [0, 1, 2] или [] если ничего не найдено.'
      },
      {
        role: 'user',
        content: semanticSearchPrompt
      }
    ];
    
    try {
      console.log(`🤖 Sending micro-request to ${provider} for semantic search...`);
      const microResponse = await sendToProviderFn(microRequestMessages, 0.3, model); // Низкая температура для точности
      const microResponseText = microResponse.choices?.[0]?.message?.content || '';
      
      console.log(`📥 Semantic search response: ${microResponseText.substring(0, 200)}`);
      
      // Парсим ответ LLM - ищем список номеров в квадратных скобках
      // Поддерживаем разные форматы: [0, 3, 5], [0,3,5], [ 0 , 3 , 5 ]
      let relevantIndices = [];
      
      // Пробуем найти список в квадратных скобках
      const indicesMatch = microResponseText.match(/\[([\d\s,]*)\]/);
      
      if (indicesMatch && indicesMatch[1]) {
        const indicesStr = indicesMatch[1].trim();
        if (indicesStr.length > 0) {
          // Извлекаем номера из списка
          relevantIndices = indicesStr
            .split(',')
            .map(idx => parseInt(idx.trim(), 10))
            .filter(idx => !isNaN(idx) && idx >= 0 && idx < batchMessages.length);
        }
      }
      
      // Если не нашли в квадратных скобках, пробуем найти просто числа
      if (relevantIndices.length === 0) {
        const numberMatches = microResponseText.match(/\b(\d+)\b/g);
        if (numberMatches) {
          relevantIndices = numberMatches
            .map(n => parseInt(n, 10))
            .filter(idx => idx >= 0 && idx < batchMessages.length)
            .filter((idx, pos, arr) => arr.indexOf(idx) === pos); // Убираем дубликаты
        }
      }
      
      console.log(`✅ Found ${relevantIndices.length} relevant messages out of ${batchMessages.length} (indices: [${relevantIndices.join(', ')}])`);
      
      // Возвращаем только релевантные сообщения
      const relevantMessages = relevantIndices.map(idx => batchMessages[idx]);
      
      return {
        messages: batchMessages, // Все сообщения из пачки (для hasMore проверки)
        totalTokens: batchResult.totalTokens || offsetTokens,
        hasMore: batchResult.hasMore || false,
        relevantMessages: relevantMessages // Только релевантные
      };
    } catch (err) {
      console.error('❌ Error in semantic search:', err);
      // При ошибке возвращаем все сообщения из пачки как потенциально релевантные
      return {
        messages: batchMessages,
        totalTokens: batchResult.totalTokens || offsetTokens,
        hasMore: batchResult.hasMore || false,
        relevantMessages: batchMessages // Fallback: все сообщения
      };
    }
  }
  
  // Получение сообщений без поиска (для будущего использования)
  static async getLTMessages(db, model, offsetTokens = 0) {
    const maxContextTokens = getModelContextLimit(model);
    const availableTokens = Math.floor(maxContextTokens * 1.5);
    
    const result = await db.getLTMessagesByTokens(availableTokens, offsetTokens);
    
    return {
      messages: result.messages || [],
      totalTokens: result.totalTokens || 0,
      hasMore: result.hasMore || false
    };
  }
}
