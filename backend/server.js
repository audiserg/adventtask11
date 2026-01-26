import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { encoding_for_model } from '@dqbd/tiktoken';
import * as db from './database.js';
import { LTMStrategy } from './ltm_strategy.js';
import * as mcpClient from './mcp-client.js';
import * as mcpConfig from './mcp-config.js';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// Система ограничений по IP
const DAILY_LIMIT = parseInt(process.env.DAILY_MESSAGE_LIMIT || '10', 10);
const ipRequestCounts = new Map(); // { ip: { date: 'YYYY-MM-DD', count: number } }

// Функция для получения IP адреса
function getClientIp(req) {
  return req.headers['x-forwarded-for']?.split(',')[0] || 
         req.headers['x-real-ip'] || 
         req.connection?.remoteAddress || 
         req.socket?.remoteAddress ||
         'unknown';
}

// Функция для получения текущей даты в формате YYYY-MM-DD
function getCurrentDate() {
  return new Date().toISOString().split('T')[0];
}

// Функция для проверки лимита (без увеличения счетчика)
function checkLimit(ip) {
  const today = getCurrentDate();
  const ipData = ipRequestCounts.get(ip);

  if (!ipData || ipData.date !== today) {
    // Новый день или новый IP
    return { allowed: true, count: 0, remaining: DAILY_LIMIT };
  }

  if (ipData.count >= DAILY_LIMIT) {
    return { allowed: false, count: ipData.count, remaining: 0 };
  }

  return { allowed: true, count: ipData.count, remaining: DAILY_LIMIT - ipData.count };
}

// Функция для увеличения счетчика запросов
function incrementLimit(ip) {
  const today = getCurrentDate();
  const ipData = ipRequestCounts.get(ip);

  if (!ipData || ipData.date !== today) {
    // Новый день или новый IP - создаем новую запись
    ipRequestCounts.set(ip, { date: today, count: 1 });
    return { count: 1, remaining: DAILY_LIMIT - 1 };
  }

  // Увеличиваем счетчик
  ipData.count++;
  ipRequestCounts.set(ip, ipData);
  return { count: ipData.count, remaining: DAILY_LIMIT - ipData.count };
}

// Очистка старых записей (запускается каждый час)
setInterval(() => {
  const today = getCurrentDate();
  for (const [ip, data] of ipRequestCounts.entries()) {
    if (data.date !== today) {
      ipRequestCounts.delete(ip);
    }
  }
}, 60 * 60 * 1000); // Каждый час

// Middleware
app.use(cors({
  origin: '*', // В production укажите конкретный домен
  methods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
// Увеличиваем лимит размера тела запроса для больших сообщений (50MB)
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Middleware для логирования запросов
app.use((req, res, next) => {
  const start = Date.now();
  const timestamp = new Date().toISOString();
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`[${timestamp}] ${req.method} ${req.originalUrl} -> ${res.statusCode} (${duration}ms)`);
  });
  
  next();
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Memory API endpoints
// Сохранение сообщения в память
app.post('/api/memory/save', async (req, res) => {
  try {
    const { role, content, sessionId, isSummarization } = req.body;
    
    if (!role || !content) {
      return res.status(400).json({
        error: 'Invalid request. Role and content are required.'
      });
    }
    
    if (role !== 'user' && role !== 'assistant' && role !== 'system') {
      return res.status(400).json({
        error: 'Invalid role. Must be "user", "assistant", or "system".'
      });
    }
    
    // Проверяем, не является ли сообщение суммаризацией
    const isSummarizationFlag = isSummarization === true || isSummarization === 1;
    
    // Не сохраняем суммаризации в LTM
    if (isSummarizationFlag) {
      console.log('⚠️ Skipping summarization message from LTM (via /api/memory/save)');
      return res.json({ 
        success: false, 
        skipped: true,
        message: 'Summarization messages are not saved to LTM' 
      });
    }
    
    // Вычисляем количество токенов (используем модель по умолчанию для оценки)
    const tokenCount = estimateTokens(content, 'gpt-3.5-turbo');
    
    const result = await db.saveMessage(role, content, sessionId || null, false, tokenCount);
    
    if (result.success) {
      res.json({ success: true, id: result.id });
    } else {
      res.status(500).json({ error: result.error });
    }
  } catch (error) {
    console.error('❌ Error saving message to memory:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Получение сообщений из памяти
app.get('/api/memory/messages', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit || '100', 10);
    const offset = parseInt(req.query.offset || '0', 10);
    const sessionId = req.query.sessionId || null;
    const search = req.query.search || null;
    
    let result;
    if (search) {
      result = await db.searchMessages(search, limit);
    } else {
      result = await db.getMessages(limit, offset, sessionId);
    }
    
    if (result.success) {
      res.json({
        success: true,
        messages: result.messages
      });
    } else {
      res.status(500).json({ error: result.error });
    }
  } catch (error) {
    console.error('❌ Error getting messages from memory:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Очистка памяти
app.delete('/api/memory/clear', async (req, res) => {
  try {
    console.log('🗑️ Received request to clear memory');
    const result = await db.clearMessages();
    
    if (result.success) {
      console.log(`✅ Memory cleared successfully. Deleted ${result.deletedCount} messages`);
      res.json({
        success: true,
        deletedCount: result.deletedCount
      });
    } else {
      console.error(`❌ Failed to clear memory: ${result.error}`);
      res.status(500).json({ 
        success: false,
        error: result.error 
      });
    }
  } catch (error) {
    console.error('❌ Error clearing memory:', error);
    console.error('Stack:', error.stack);
    res.status(500).json({ 
      success: false,
      error: 'Internal server error',
      message: error.message 
    });
  }
});

// Получение количества сообщений в памяти
app.get('/api/memory/count', async (req, res) => {
  try {
    const sessionId = req.query.sessionId || null;
    const result = await db.getMessageCount(sessionId);
    
    if (result.success) {
      res.json({
        success: true,
        count: result.count
      });
    } else {
      res.status(500).json({ error: result.error });
    }
  } catch (error) {
    console.error('❌ Error getting memory count:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint для получения списка доступных моделей
app.get('/api/models', async (req, res) => {
  try {
    console.log('📋 Request for available models');
    
    // Попытка получить список моделей из Hugging Face API
    const hfApiKey = process.env.HUGGINGFACE_API_KEY;
    let hfModels = [];
    
    if (hfApiKey) {
      try {
        // Попытка получить список через Hub API
        const hubResponse = await fetch('https://huggingface.co/api/models?filter=text-generation-inference&sort=downloads&direction=-1&limit=50', {
          headers: {
            'Authorization': `Bearer ${hfApiKey}`,
          },
        });
        
        if (hubResponse.ok) {
          const hubData = await hubResponse.json();
          // Фильтруем только chat модели (исключаем gpt2, base модели и т.д.)
          // Используем строгую фильтрацию для проверенных моделей
          hfModels = hubData
            .filter(model => {
              if (!model.id || !model.id.includes('/')) return false;
              const modelId = model.id.toLowerCase();
              
              // Исключаем модели, которые точно не chat
              const excludePatterns = [
                'gpt2',
                'gpt-2',
                'base',
                'vision',
                'embedding',
                'tokenizer',
                'openai-community/gpt2',
                'qwen3-', // Qwen3 модели без -Instruct не поддерживают chat
                'qwen2-0', // Qwen2.0 без -Instruct
                '-0.6b',
                '-1.5b',
                '-3b-instruct', // Могут быть недоступны
              ];
              
              // Строгие паттерны для включения - только проверенные форматы
              const includePatterns = [
                'qwen2.5-', // Qwen 2.5 с -Instruct
                'llama-3.1-', // Llama 3.1
                'llama-3.2-', // Llama 3.2
                'llama-2-7b-chat', // Llama 2 chat
                'mistral-7b-instruct',
                'mixtral-8x7b-instruct',
                'gemma-2-', // Gemma 2
                'deepseek-', // DeepSeek модели
                'glm-', // GLM модели
              ];
              
              const hasExclude = excludePatterns.some(pattern => modelId.includes(pattern));
              
              // Для Qwen - только с -Instruct в конце
              if (modelId.includes('qwen') && !modelId.includes('-instruct')) {
                return false;
              }
              
              // Для Llama - только с -Instruct или -chat
              if (modelId.includes('llama') && !modelId.includes('-instruct') && !modelId.includes('-chat')) {
                return false;
              }
              
              // Для Mistral - только с -Instruct
              if (modelId.includes('mistral') && !modelId.includes('-instruct')) {
                return false;
              }
              
              // Для Gemma - только с -it (instruction tuned)
              if (modelId.includes('gemma') && !modelId.includes('-it')) {
                return false;
              }
              
              const hasInclude = includePatterns.some(pattern => modelId.includes(pattern));
              
              return !hasExclude && hasInclude;
            })
            .map(model => model.id)
            .slice(0, 30); // Ограничиваем до 30 проверенных моделей
        }
      } catch (error) {
        console.warn('⚠️ Could not fetch models from Hub API:', error.message);
      }
    }
    
    // Если не удалось получить динамически или список пустой, используем предустановленный список
    // Используем только модели, которые точно поддерживают chat completion через router API
    // Эти модели проверены и работают через router.huggingface.co/v1/chat/completions
    if (hfModels.length === 0) {
      console.log('📋 Using predefined model list (no models from Hub API)');
      hfModels = [
        // Qwen 2.5 модели (проверенные)
        'Qwen/Qwen2.5-72B-Instruct',
        'Qwen/Qwen2.5-32B-Instruct',
        'Qwen/Qwen2.5-14B-Instruct',
        'Qwen/Qwen2.5-7B-Instruct',
        'Qwen/Qwen2.5-3B-Instruct',
        // Llama модели (проверенные)
        'meta-llama/Llama-3.1-8B-Instruct',
        'meta-llama/Llama-3.1-70B-Instruct',
        'meta-llama/Llama-3.2-3B-Instruct',
        'meta-llama/Llama-2-7b-chat-hf',
        // Gemma модели (проверенные)
        'google/gemma-2-2b-it',
        'google/gemma-2-9b-it',
        // Mistral модели (проверенные)
        'mistralai/Mistral-7B-Instruct-v0.2',
        'mistralai/Mixtral-8x7B-Instruct-v0.1',
        // DeepSeek модели (проверенные)
        'deepseek-ai/DeepSeek-V3-0324',
        'deepseek-ai/DeepSeek-V2-Lite',
        'deepseek-ai/DeepSeek-R1',
        // GLM модели (проверенные)
        'zai-org/GLM-4.7-Flash:novita',
      ];
    } else {
      // Дополнительно фильтруем динамически полученные модели
      // Удаляем модели, которые точно не работают
      hfModels = hfModels.filter(model => {
        const modelId = model.toLowerCase();
        // Исключаем проблемные модели
        const problematicPatterns = [
          'qwen3-',
          'qwen2-0',
          '-0.6b',
          '-1.5b',
          'qwen2.5-1.5b',
        ];
        return !problematicPatterns.some(pattern => modelId.includes(pattern));
      });
      
      // Добавляем проверенные модели в начало списка
      const verifiedModels = [
        'Qwen/Qwen2.5-7B-Instruct',
        'Qwen/Qwen2.5-14B-Instruct',
        'meta-llama/Llama-3.1-8B-Instruct',
        'google/gemma-2-2b-it',
        'mistralai/Mistral-7B-Instruct-v0.2',
        'zai-org/GLM-4.7-Flash:novita',
      ];
      
      // Объединяем проверенные модели с динамическими, убирая дубликаты
      const allModels = [...new Set([...verifiedModels, ...hfModels])];
      hfModels = allModels.slice(0, 30);
    }
    
    // Список моделей DeepSeek
    const deepseekModels = [
      'deepseek-ai/DeepSeek-V3-0324',
      'deepseek-chat',
      'deepseek-reasoner',
      'deepseek-chat-reasoner',
      'deepseek-ai/DeepSeek-V2-Lite',
      'deepseek-ai/DeepSeek-R1',
    ];
    
    const response = {
      providers: {
        deepseek: {
          name: 'DeepSeek',
          models: deepseekModels,
          presets: PRESET_MODELS.deepseek,
        },
        huggingface: {
          name: 'Hugging Face',
          models: hfModels,
          presets: PRESET_MODELS.huggingface,
        },
      },
      defaultProvider: process.env.DEFAULT_PROVIDER || 'deepseek',
    };
    
    console.log(`✅ Returning ${deepseekModels.length} DeepSeek models and ${hfModels.length} Hugging Face models`);
    res.json(response);
  } catch (error) {
    console.error('❌ Error fetching models:', error.message);
    res.status(500).json({ 
      error: 'Failed to fetch models',
      message: error.message 
    });
  }
});

// Предустановленные модели для быстрого доступа
const PRESET_MODELS = {
  deepseek: {
    top: 'deepseek-ai/DeepSeek-V3-0324',
    medium: 'deepseek-chat',
    light: 'deepseek-chat',
  },
  huggingface: {
    top: 'Qwen/Qwen2.5-72B-Instruct',
    medium: 'Qwen/Qwen2.5-7B-Instruct',
    light: 'google/gemma-2-2b-it',
  },
};

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
export function getModelContextLimit(model) {
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

// Функция для примерного расчета токенов
function estimateTokens(text, model = 'gpt-3.5-turbo') {
  if (!text || typeof text !== 'string') {
    return 0;
  }
  
  try {
    // Используем tiktoken для более точного подсчета
    // Используем модель по умолчанию, если не указана другая
    // Для моделей, которые не поддерживаются, используем gpt-3.5-turbo как fallback
    let enc;
    try {
      enc = encoding_for_model(model);
    } catch (modelError) {
      // Если модель не поддерживается, используем gpt-3.5-turbo
      console.warn(`⚠️ Model ${model} not supported by tiktoken, using gpt-3.5-turbo encoding`);
      enc = encoding_for_model('gpt-3.5-turbo');
    }
    const tokens = enc.encode(text);
    enc.free(); // Освобождаем память
    return tokens.length;
  } catch (error) {
    console.warn('⚠️ Error using tiktoken, falling back to character-based estimation:', error.message);
    // Fallback: примерная оценка на основе символов
    // Английский: ~0.3 токена на символ, русский/другие: ~0.4-0.6 токена на символ
    const hasCyrillic = /[а-яА-ЯёЁ]/.test(text);
    const hasChinese = /[\u4e00-\u9fff]/.test(text);
    const coefficient = hasChinese ? 0.6 : (hasCyrillic ? 0.4 : 0.3);
    return Math.ceil(text.length * coefficient);
  }
}

// Функция для извлечения информации о токенах из ответа API
function extractTokenUsage(apiResponse, messages, aiResponse, model = 'gpt-3.5-turbo') {
  // Получаем лимит контекстного окна для модели
  const maxContextTokens = getModelContextLimit(model);
  
  // Проверяем, есть ли поле usage в ответе API
  let promptTokens, completionTokens, totalTokens, estimated;
  
  if (apiResponse.usage && typeof apiResponse.usage === 'object') {
    promptTokens = apiResponse.usage.prompt_tokens || 0;
    completionTokens = apiResponse.usage.completion_tokens || 0;
    totalTokens = apiResponse.usage.total_tokens || 0;
    estimated = false; // Точные данные от API
  } else {
    // Если usage нет, рассчитываем локально
    // Подсчитываем токены для всех сообщений (prompt)
    const promptText = messages
      .map(msg => `${msg.role}: ${msg.content}`)
      .join('\n');
    promptTokens = estimateTokens(promptText, model);
    
    // Подсчитываем токены для ответа (completion)
    completionTokens = estimateTokens(aiResponse, model);
    
    totalTokens = promptTokens + completionTokens;
    estimated = true; // Примерный расчет
  }
  
  // Рассчитываем процент использования контекстного окна
  const contextUsagePercent = Math.min((totalTokens / maxContextTokens) * 100, 100);
  
  return {
    prompt_tokens: promptTokens,
    completion_tokens: completionTokens,
    total_tokens: totalTokens,
    estimated: estimated,
    max_context_tokens: maxContextTokens,
    context_usage_percent: Math.round(contextUsagePercent * 10) / 10, // Округляем до 1 знака после запятой
  };
}

// Функция для проверки, является ли сообщение или ответ суммаризацией
function isSummarizationMessage(userMessage, assistantResponse = null) {
  // Проверяем флаг isSummarization в сообщении пользователя
  if (userMessage && (
    userMessage.isSummarization === true || 
    userMessage.isSummarization === 1
  )) {
    return true;
  }
  
  // Проверяем содержимое сообщения пользователя на ключевые слова
  if (userMessage && userMessage.content) {
    const content = userMessage.content.toLowerCase();
    if (content.includes('суммар') ||
        content.includes('кратк') ||
        content.includes('краткое резюме') ||
        content.includes('summarize') ||
        content.includes('summary')) {
      return true;
    }
  }
  
  // Проверяем сам ответ ассистента на признаки суммаризации
  if (assistantResponse) {
    const response = assistantResponse.toLowerCase();
    if (response.includes('краткая суммаризация') ||
        response.includes('суммаризация контекста') ||
        response.includes('краткое резюме') ||
        response.startsWith('краткая суммаризация') ||
        response.includes('summary of') ||
        response.includes('context summary')) {
      return true;
    }
  }
  
  return false;
}

// Функция для отправки запроса к DeepSeek API
async function sendToDeepSeek(messagesWithSystem, temperature, model) {
  const apiKey = process.env.DEEPSEEK_API_KEY;
  if (!apiKey) {
    throw new Error('DEEPSEEK_API_KEY is not set in environment variables');
  }

  const deepseekUrl = 'https://api.deepseek.com/v1/chat/completions';
  const requestBody = {
    model: model || process.env.DEEPSEEK_MODEL || 'deepseek-chat',
    messages: messagesWithSystem,
    stream: false,
  };
  
  if (temperature !== undefined && temperature !== null) {
    requestBody.temperature = temperature;
  }
  
  console.log('🚀 Sending request to DeepSeek API:');
  console.log('URL:', deepseekUrl);
  console.log('Model:', requestBody.model);
  console.log('Messages count:', messagesWithSystem.length);
  
  const response = await fetch(deepseekUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error('❌ DeepSeek API error:', response.status, errorText);
    throw new Error(`DeepSeek API error: ${response.status} - ${errorText}`);
  }

  return await response.json();
}

// Функция для отправки запроса к Hugging Face API
async function sendToHuggingFace(messagesWithSystem, temperature, model) {
  const apiKey = process.env.HUGGINGFACE_API_KEY;
  if (!apiKey) {
    throw new Error('HUGGINGFACE_API_KEY is not set in environment variables');
  }

  const hfUrl = 'https://router.huggingface.co/v1/chat/completions';
  const requestBody = {
    model: model || process.env.HUGGINGFACE_MODEL || 'Qwen/Qwen2.5-7B-Instruct',
    messages: messagesWithSystem,
    stream: false,
  };
  
  if (temperature !== undefined && temperature !== null) {
    requestBody.temperature = temperature;
  }
  
  console.log('🚀 Sending request to Hugging Face API:');
  console.log('URL:', hfUrl);
  console.log('Model:', requestBody.model);
  console.log('Messages count:', messagesWithSystem.length);
  
  const response = await fetch(hfUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error('❌ Hugging Face API error:', response.status, errorText);
    console.error('❌ Model used:', requestBody.model);
    
    // Более детальная обработка ошибок
    let errorMessage = `Hugging Face API error: ${response.status}`;
    try {
      const errorData = JSON.parse(errorText);
      // errorData.error может быть объектом с полем message
      if (errorData.error) {
        if (typeof errorData.error === 'string') {
          errorMessage += ` - ${errorData.error}`;
        } else if (errorData.error.message) {
          errorMessage += ` - ${errorData.error.message}`;
        } else if (errorData.error.type) {
          errorMessage += ` - ${errorData.error.type}: ${errorData.error.message || errorData.error.code || ''}`;
        } else {
          errorMessage += ` - ${JSON.stringify(errorData.error)}`;
        }
      } else if (errorData.message) {
        errorMessage += ` - ${errorData.message}`;
      } else {
        errorMessage += ` - ${errorText}`;
      }
    } catch (e) {
      errorMessage += ` - ${errorText}`;
    }
    
    // Если модель не поддерживается или не найдена, предлагаем альтернативу
    if (response.status === 404 || 
        response.status === 400 && (
          errorText.includes('not found') || 
          errorText.includes('Model') || 
          errorText.includes('not a chat model') ||
          errorText.includes('model_not_supported')
        )) {
      errorMessage += `. Модель "${requestBody.model}" не поддерживает chat completion или недоступна. Попробуйте другую модель из списка.`;
    }
    
    throw new Error(errorMessage);
  }

  return await response.json();
}

// Chat endpoint - proxies to DeepSeek or Hugging Face API
app.post('/api/chat', async (req, res) => {
  try {
    console.log('📨 Received chat request');
    const { messages, temperature, systemPrompt, provider, model, useMemory } = req.body;
    console.log(`📝 Messages count: ${messages?.length || 0}`);
    console.log(`🌡️ Temperature: ${temperature ?? 'default'}`);
    console.log(`📋 System prompt: ${systemPrompt ? 'custom' : 'default'}`);
    console.log(`🔌 Provider: ${provider || 'default (deepseek)'}`);
    console.log(`🤖 Model: ${model || 'default'}`);
    console.log(`💾 Use memory: ${useMemory ? 'yes' : 'no'}`);
    
    // Логируем содержимое сообщений
    if (messages && Array.isArray(messages)) {
      console.log('💬 Messages content:');
      messages.forEach((msg, index) => {
        console.log(`  [${index + 1}] ${msg.role}: ${msg.content?.substring(0, 200)}${msg.content?.length > 200 ? '...' : ''}`);
      });
    }

    if (!messages || !Array.isArray(messages)) {
      return res.status(400).json({ 
        error: 'Invalid request. Messages array is required.' 
      });
    }

    // Определяем провайдера
    const selectedProvider = provider || process.env.DEFAULT_PROVIDER || 'deepseek';
    
    // Определяем модель
    let selectedModel = model;
    if (!selectedModel && selectedProvider === 'deepseek') {
      selectedModel = process.env.DEEPSEEK_MODEL || 'deepseek-chat';
    } else if (!selectedModel && selectedProvider === 'huggingface') {
      selectedModel = process.env.HUGGINGFACE_MODEL || 'Qwen/Qwen2.5-7B-Instruct';
    }

    // Сохраняем только последнее сообщение пользователя в память (исключая суммаризации)
    // Ответ ассистента будет сохранен после получения ответа от LLM
    if (useMemory) {
      // Находим последнее сообщение пользователя
      const lastUserMessage = messages.filter(m => m.role === 'user').pop();
      
      if (lastUserMessage) {
        try {
          // Проверяем, не является ли сообщение суммаризацией
          const isSummarization = lastUserMessage.isSummarization === true || lastUserMessage.isSummarization === 1;
          
          if (!isSummarization) {
            // Вычисляем количество токенов
            const tokenCount = estimateTokens(lastUserMessage.content, selectedModel);
            const result = await db.saveMessage('user', lastUserMessage.content, null, false, tokenCount);
            
            if (result.success) {
              console.log(`💾 Saved user message to LTM (${tokenCount} tokens)`);
            } else if (result.skipped) {
              console.log(`⚠️ Skipped summarization message from LTM`);
            } else {
              console.error(`❌ Error saving user message to LTM:`, result.error);
            }
          } else {
            console.log(`⚠️ Skipping summarization message from LTM`);
          }
        } catch (err) {
          console.error(`❌ Error saving user message to memory:`, err);
        }
      }
    }

    // Используем переданный системный промпт, если он есть
    let messagesWithSystem = messages;
    
    // Получаем доступные MCP инструменты
    let mcpToolsPrompt = '';
    try {
      const toolsResult = await mcpClient.listAllTools();
      if (toolsResult.success && toolsResult.tools && toolsResult.tools.length > 0) {
        mcpToolsPrompt = '\n\n=== ДОСТУПНЫЕ ИНСТРУМЕНТЫ (MCP) ===\n\n';
        mcpToolsPrompt += 'У вас есть доступ к следующим инструментам через MCP (Model Context Protocol):\n\n';
        
        // Группируем инструменты по серверам
        const toolsByServer = {};
        for (const tool of toolsResult.tools) {
          const serverName = tool.serverName || tool.serverId || 'Unknown';
          if (!toolsByServer[serverName]) {
            toolsByServer[serverName] = [];
          }
          toolsByServer[serverName].push(tool);
        }
        
        for (const [serverName, serverTools] of Object.entries(toolsByServer)) {
          mcpToolsPrompt += `\n[${serverName}]\n`;
          for (const tool of serverTools) {
            mcpToolsPrompt += `\n• ${tool.name}: ${tool.description}\n`;
            
            // Добавляем информацию о параметрах
            const inputSchema = tool.inputSchema || {};
            const properties = inputSchema.properties || {};
            const required = inputSchema.required || [];
            
            if (Object.keys(properties).length > 0) {
              mcpToolsPrompt += '  Параметры:\n';
              for (const [paramName, paramSchema] of Object.entries(properties)) {
                const isRequired = required.includes(paramName);
                const paramType = paramSchema.type || 'string';
                const paramDesc = paramSchema.description || '';
                mcpToolsPrompt += `    - ${paramName} (${paramType}${isRequired ? ', обязательный' : ', опциональный'}): ${paramDesc}\n`;
              }
            }
            
            mcpToolsPrompt += `  Использование: **mcp_call**(${tool.name}, serverId="${tool.serverId}", параметры)\n`;
            mcpToolsPrompt += `  Пример: **mcp_call**(${tool.name}, serverId="${tool.serverId}", {"param1": "value1"})\n`;
          }
        }
        
        mcpToolsPrompt += '\n\nВАЖНО: Для вызова инструмента используйте формат:\n';
        mcpToolsPrompt += '**mcp_call**(название_инструмента, serverId="id_сервера", {"параметр1": "значение1", "параметр2": "значение2"})\n\n';
        mcpToolsPrompt += 'Система автоматически вызовет инструмент и вернет результат. Вы можете использовать результат для ответа пользователю.\n';
      }
    } catch (error) {
      console.error('❌ Error loading MCP tools for system prompt:', error);
    }
    
    // Системный промпт для памяти (добавляется автоматически если useMemory=true)
    let memorySystemPrompt = '';
    if (useMemory) {
      memorySystemPrompt = 
        'У вас есть доступ к долгосрочной памяти (LTM) с историей предыдущих сообщений.\n\n' +
        'Если вам нужна информация из долгосрочной памяти, используйте команду:\n' +
        '**ltm_search**(ваш запрос)\n\n' +
        'Например:\n' +
        '- **ltm_search**(проект на Python)\n' +
        '- **ltm_search**(обсуждение архитектуры)\n' +
        '- **ltm_search**(Москва)\n' +
        '- **ltm_search**(город который хотел обсудить)\n\n' +
        'ВАЖНО: Команда должна быть в формате **ltm_search**(текст запроса), где текст запроса - это ваш вопрос или ключевые слова для поиска в памяти.\n\n' +
        'Система автоматически загрузит релевантные сообщения из памяти через семантический поиск. Если нужная информация не найдена в первой пачке, система может загрузить следующую пачку сообщений.\n\n' +
        'ВАЖНО: Сообщения суммаризации не сохраняются в LTM, используйте только обычные сообщения.';
    }
    
    // Объединяем системные промпты
    let finalSystemPrompt = '';
    const promptParts = [];
    
    if (memorySystemPrompt) {
      promptParts.push(memorySystemPrompt);
    }
    
    if (mcpToolsPrompt) {
      promptParts.push(mcpToolsPrompt);
    }
    
    if (systemPrompt && systemPrompt.trim().length > 0) {
      promptParts.push(systemPrompt);
    }
    
    finalSystemPrompt = promptParts.join('\n\n');
    
    // Формируем финальный массив сообщений с системным промптом
    if (finalSystemPrompt && finalSystemPrompt.trim().length > 0) {
      messagesWithSystem = [
        {
          role: 'system',
          content: finalSystemPrompt
        },
        ...messages
      ];
    } else {
      messagesWithSystem = messages;
    }
    
    console.log(`📋 Total messages in context: ${messagesWithSystem.length}`);

    // Отправляем запрос в зависимости от провайдера
    let data;
    if (selectedProvider === 'huggingface') {
      console.log('🤖 Sending request to Hugging Face API...');
      data = await sendToHuggingFace(messagesWithSystem, temperature, selectedModel);
    } else {
      console.log('🤖 Sending request to DeepSeek API...');
      data = await sendToDeepSeek(messagesWithSystem, temperature, selectedModel);
    }

    let aiResponse = data.choices?.[0]?.message?.content || 'No response';
    console.log(`✅ Received response from ${selectedProvider} (${aiResponse.length} chars)`);
    console.log(`📄 Full response:`);
    console.log(aiResponse);
    console.log('─'.repeat(80));
    
    // Обработка вызова MCP инструментов
    // Формат: **mcp_call**(toolName, serverId="serverId", {"param1": "value1"})
    const mcpCallPattern = /\*\*mcp_call\*\*\(([^,]+),\s*serverId\s*=\s*"([^"]+)",\s*(\{[^}]+\})\)/;
    let mcpMatch = aiResponse.match(mcpCallPattern);
    
    if (mcpMatch) {
      const toolName = mcpMatch[1].trim();
      const serverId = mcpMatch[2].trim();
      let argsJson = mcpMatch[3].trim();
      
      try {
        // Парсим JSON аргументы
        const args = JSON.parse(argsJson);
        
        console.log(`🔧 MCP tool call detected: ${toolName} on server ${serverId}`);
        console.log(`📋 Arguments:`, args);
        
        // Вызываем инструмент
        const toolResult = await mcpClient.callTool(serverId, toolName, args);
        
        if (toolResult.success) {
          const resultContent = toolResult.result?.content?.[0]?.text || JSON.stringify(toolResult.result);
          console.log(`✅ MCP tool result:`, resultContent);
          
          // Добавляем результат в контекст и запрашиваем продолжение ответа
          const toolResultMessage = `Результат выполнения инструмента ${toolName}:\n${resultContent}`;
          
          // Добавляем результат в историю сообщений и запрашиваем продолжение
          const updatedMessages = [
            ...messagesWithSystem,
            {
              role: 'assistant',
              content: aiResponse.substring(0, mcpMatch.index) + `[Вызван инструмент ${toolName}]`
            },
            {
              role: 'user',
              content: toolResultMessage + '\n\nПродолжи ответ пользователю, используя результат инструмента.'
            }
          ];
          
          // Запрашиваем продолжение ответа с результатом инструмента
          let continuationData;
          if (selectedProvider === 'huggingface') {
            continuationData = await sendToHuggingFace(updatedMessages, temperature, selectedModel);
          } else {
            continuationData = await sendToDeepSeek(updatedMessages, temperature, selectedModel);
          }
          
          aiResponse = continuationData.choices?.[0]?.message?.content || aiResponse;
          console.log(`✅ Continuation response received`);
        } else {
          console.error(`❌ MCP tool call failed:`, toolResult);
          aiResponse = aiResponse.replace(
            mcpMatch[0],
            `[Ошибка вызова инструмента ${toolName}: ${toolResult.error || 'Unknown error'}]`
          );
        }
      } catch (error) {
        console.error(`❌ Error calling MCP tool:`, error);
        aiResponse = aiResponse.replace(
          mcpMatch[0],
          `[Ошибка вызова инструмента: ${error.message}]`
        );
      }
    }
    
    // Обработка команды **ltm_search**(query) или **search**(query) в ответе модели
    // Поддерживаем оба варианта для совместимости
    const ltmSearchPattern = /\*\*ltm_search\*\*\(([^)]+)\)/;
    const searchPattern = /\*\*search\*\*\(([^)]+)\)/;
    let ltmMatch = aiResponse.match(ltmSearchPattern);
    if (!ltmMatch) {
      // Пробуем альтернативный формат **search**(query)
      ltmMatch = aiResponse.match(searchPattern);
    }
    
    if (ltmMatch && useMemory) {
      let query = ltmMatch[1].trim().replace(/['"]/g, ''); // Убираем кавычки если есть
      
      // Если в запросе только числа (ID сообщений), используем последний вопрос пользователя
      if (/^\d+[\s,]*\d*$/.test(query)) {
        console.log(`⚠️ LLM returned message IDs instead of query: "${query}", using user's question instead`);
        const lastUserMessage = messages.filter(m => m.role === 'user').pop();
        query = lastUserMessage?.content || query;
      }
      
      console.log(`🔍 LTM search requested: "${query}"`);
      
      // Получаем последний вопрос пользователя для семантического поиска
      const lastUserMessage = messages.filter(m => m.role === 'user').pop();
      const userQuery = lastUserMessage?.content || query;
      
      try {
        // Используем стратегию для семантического поиска через LLM (максимум 10 пачек)
        let ltmMessages = [];
        let offsetTokens = 0;
        const maxBatches = 10;
        let batchCount = 0;
        
        // Функция для отправки запроса к провайдеру (для микрозапросов)
        const sendToProvider = selectedProvider === 'huggingface' 
          ? sendToHuggingFace 
          : sendToDeepSeek;
        
        while (batchCount < maxBatches) {
          console.log(`🔍 Semantic search batch ${batchCount + 1}: searching in LTM (offset: ${offsetTokens} tokens)...`);
          
          const batchResult = await LTMStrategy.searchLTM(
            db, 
            selectedModel, 
            userQuery, 
            offsetTokens, 
            selectedProvider,
            sendToProvider,
            temperature
          );
          
          if (batchResult.messages.length === 0) {
            console.log(`⚠️ No more messages in LTM, stopping search`);
            break; // Больше нет сообщений
          }
          
          // Добавляем только релевантные сообщения, найденные LLM
          if (batchResult.relevantMessages && batchResult.relevantMessages.length > 0) {
            ltmMessages.push(...batchResult.relevantMessages);
            console.log(`✅ Batch ${batchCount + 1}: found ${batchResult.relevantMessages.length} relevant messages (total relevant: ${ltmMessages.length})`);
            
            // Если нашли достаточно релевантных сообщений, можно остановиться
            if (ltmMessages.length >= 10) {
              console.log(`✅ Found enough relevant messages (${ltmMessages.length}), stopping search`);
              break;
            }
          } else {
            console.log(`⚠️ Batch ${batchCount + 1}: no relevant messages found in this batch`);
          }
          
          // Переходим к следующей пачке
          offsetTokens = batchResult.totalTokens;
          batchCount++;
          
          // Если больше нет сообщений, останавливаемся
          if (!batchResult.hasMore) {
            console.log(`⚠️ No more batches available, stopping search`);
            break;
          }
        }
        
        if (ltmMessages.length > 0) {
          console.log(`📚 Loaded ${ltmMessages.length} messages from LTM for query "${query}"`);
          
          // Добавляем LTM сообщения в контекст и отправляем повторный запрос
          const extendedMessages = [
            ...messagesWithSystem.slice(0, 1), // Системный промпт
            ...ltmMessages.map(msg => ({ 
              role: msg.role, 
              content: msg.content 
            })),
            ...messages // Текущие сообщения
          ];
          
          console.log(`📋 Extended context: ${extendedMessages.length} total messages (${ltmMessages.length} from LTM + ${messages.length} current)`);
          
          // Повторный запрос к LLM
          let retryData;
          if (selectedProvider === 'huggingface') {
            console.log('🔄 Sending retry request to Hugging Face API with LTM context...');
            retryData = await sendToHuggingFace(extendedMessages, temperature, selectedModel);
          } else {
            console.log('🔄 Sending retry request to DeepSeek API with LTM context...');
            retryData = await sendToDeepSeek(extendedMessages, temperature, selectedModel);
          }
          
          aiResponse = retryData.choices?.[0]?.message?.content || aiResponse;
          // Удаляем обе возможные команды поиска
          aiResponse = aiResponse.replace(ltmSearchPattern, '').replace(searchPattern, '').trim();
          
          // Обновляем data для правильного расчета токенов
          data = retryData;
          messagesWithSystem = extendedMessages;
          
          // Сохраняем финальный ответ ассистента в память (проверяем, не является ли он суммаризацией)
          if (useMemory && aiResponse) {
            try {
              const lastUserMessage = messages.filter(m => m.role === 'user').pop();
              
              if (isSummarizationMessage(lastUserMessage, aiResponse)) {
                console.log(`⚠️ Skipping summarization response from LTM`);
              } else {
                const tokenCount = estimateTokens(aiResponse, selectedModel);
                const result = await db.saveMessage('assistant', aiResponse, null, false, tokenCount);
                if (result.success) {
                  console.log(`💾 Saved assistant response to LTM (${tokenCount} tokens)`);
                }
              }
            } catch (err) {
              console.error('❌ Error saving assistant response to memory:', err);
            }
          }
          
          // Извлекаем информацию о токенах
          const tokenUsage = extractTokenUsage(data, messagesWithSystem, aiResponse, selectedModel);
          console.log(`🔢 Token usage:`, tokenUsage);
          
          // Обновляем ответ с финальным текстом
          if (data.choices && data.choices[0] && data.choices[0].message) {
            data.choices[0].message.content = aiResponse;
          }
          
          // Возвращаем ответ с флагом ltmUsed
          const responseData = {
            ...data,
            tokenUsage: tokenUsage,
            ltmUsed: true,
            ltmMessagesCount: ltmMessages.length,
            ltmQuery: query
          };
          
          return res.json(responseData);
        } else {
          // LTM пуст или поиск не дал результатов
          console.log(`⚠️ No messages found in LTM for query "${query}"`);
          // Удаляем обе возможные команды поиска
          aiResponse = aiResponse.replace(ltmSearchPattern, '').replace(searchPattern, '').trim();
          
          // Сохраняем ответ ассистента в память (проверяем, не является ли он суммаризацией)
          if (useMemory && aiResponse) {
            try {
              const lastUserMessage = messages.filter(m => m.role === 'user').pop();
              
              if (isSummarizationMessage(lastUserMessage, aiResponse)) {
                console.log(`⚠️ Skipping summarization response from LTM`);
              } else {
                const tokenCount = estimateTokens(aiResponse, selectedModel);
                const result = await db.saveMessage('assistant', aiResponse, null, false, tokenCount);
                if (result.success) {
                  console.log(`💾 Saved assistant response to LTM (${tokenCount} tokens)`);
                }
              }
            } catch (err) {
              console.error('❌ Error saving assistant response to memory:', err);
            }
          }
          
          // Извлекаем информацию о токенах
          const tokenUsage = extractTokenUsage(data, messagesWithSystem, aiResponse, selectedModel);
          
          // Обновляем ответ с финальным текстом
          if (data.choices && data.choices[0] && data.choices[0].message) {
            data.choices[0].message.content = aiResponse;
          }
          
          // Возвращаем ответ с флагом ltmEmpty
          const responseData = {
            ...data,
            tokenUsage: tokenUsage,
            ltmEmpty: true,
            ltmQuery: query
          };
          
          return res.json(responseData);
        }
      } catch (ltmErr) {
        console.error('❌ Error processing LTM search:', ltmErr);
        // Продолжаем с обычным ответом при ошибке LTM
        // Удаляем обе возможные команды поиска
        aiResponse = aiResponse.replace(ltmSearchPattern, '').replace(searchPattern, '').trim();
      }
    }
    
    // Сохраняем ответ ассистента в память, если включена (обычный ответ без LTM)
    // Проверяем, не является ли ответ суммаризацией
    if (useMemory && aiResponse) {
      try {
        const lastUserMessage = messages.filter(m => m.role === 'user').pop();
        
        if (isSummarizationMessage(lastUserMessage, aiResponse)) {
          console.log(`⚠️ Skipping summarization response from LTM`);
        } else {
          const tokenCount = estimateTokens(aiResponse, selectedModel);
          const result = await db.saveMessage('assistant', aiResponse, null, false, tokenCount);
          if (result.success) {
            console.log(`💾 Saved assistant response to LTM (${tokenCount} tokens)`);
          }
        }
      } catch (err) {
        console.error('❌ Error saving assistant response to memory:', err);
      }
    }
    
    // Извлекаем информацию о токенах
    const tokenUsage = extractTokenUsage(data, messagesWithSystem, aiResponse, selectedModel);
    console.log(`🔢 Token usage:`, tokenUsage);
    
    // Обновляем ответ с финальным текстом
    if (data.choices && data.choices[0] && data.choices[0].message) {
      data.choices[0].message.content = aiResponse;
    }
    
    // Добавляем tokenUsage в ответ
    const responseData = {
      ...data,
      tokenUsage: tokenUsage,
    };
    
    res.json(responseData);
  } catch (error) {
    console.error('❌ Error processing chat request:', error.message);
    console.error('Stack:', error.stack);
    
    // Определяем статус код ошибки
    let statusCode = 500;
    let errorMessage = error.message;
    
    if (error.message.includes('API error:')) {
      statusCode = 502; // Bad Gateway
    } else if (error.message.includes('is not set')) {
      statusCode = 500;
      errorMessage = 'Server configuration error: API key not set';
    }
    
    res.status(statusCode).json({ 
      error: 'Internal server error',
      message: errorMessage 
    });
  }
});

// MCP API endpoints
// Получение списка всех инструментов
app.get('/api/mcp/tools', async (req, res) => {
  try {
    const serverId = req.query.serverId;
    
    if (serverId) {
      // Получаем инструменты конкретного сервера
      const result = await mcpClient.listTools(serverId);
      res.json(result);
    } else {
      // Получаем инструменты со всех серверов
      const result = await mcpClient.listAllTools();
      res.json(result);
    }
  } catch (error) {
    console.error('❌ Error listing MCP tools:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Выполнение инструмента
app.post('/api/mcp/tools/:toolName', async (req, res) => {
  try {
    const { toolName } = req.params;
    const { serverId, ...args } = req.body;

    if (!serverId) {
      return res.status(400).json({
        success: false,
        error: 'serverId обязателен',
      });
    }

    const result = await mcpClient.callTool(serverId, toolName, args);
    res.json(result);
  } catch (error) {
    console.error('❌ Error calling MCP tool:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Выполнение инструмента на конкретном сервере (альтернативный endpoint)
app.post('/api/mcp/servers/:serverId/tools/:toolName', async (req, res) => {
  try {
    const { serverId, toolName } = req.params;
    const args = req.body;

    const result = await mcpClient.callTool(serverId, toolName, args);
    res.json(result);
  } catch (error) {
    console.error('❌ Error calling MCP tool:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Статус всех подключений
app.get('/api/mcp/status', async (req, res) => {
  try {
    const serverId = req.query.serverId;
    
    if (serverId) {
      const status = mcpClient.getServerStatus(serverId);
      res.json(status);
    } else {
      const statuses = mcpClient.getAllServersStatus();
      res.json(statuses);
    }
  } catch (error) {
    console.error('❌ Error getting MCP status:', error);
    res.status(500).json({
      error: error.message,
    });
  }
});

// Управление MCP серверами
// Получение списка всех серверов
app.get('/api/mcp/servers', async (req, res) => {
  try {
    const servers = mcpConfig.getAllServers();
    const statuses = mcpClient.getAllServersStatus();
    
    // Объединяем конфигурацию с статусами
    const serversWithStatus = servers.map(server => ({
      ...server,
      connectionStatus: statuses[server.id]?.status || 'disconnected',
      connectedAt: statuses[server.id]?.connectedAt,
      error: statuses[server.id]?.error,
    }));
    
    res.json({
      success: true,
      servers: serversWithStatus,
    });
  } catch (error) {
    console.error('❌ Error getting MCP servers:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Добавление нового сервера
app.post('/api/mcp/servers', async (req, res) => {
  try {
    const { id, name, url, enabled, description } = req.body;
    
    if (!id || !name || !url) {
      return res.status(400).json({
        success: false,
        error: 'id, name и url обязательны',
      });
    }

    const result = mcpConfig.addServer({
      id,
      name,
      url,
      enabled: enabled !== undefined ? enabled : true,
      description: description || '',
    });

    if (result.success) {
      // Если сервер включен, подключаемся к нему
      if (result.server.enabled) {
        await mcpClient.connect(result.server.id, result.server.url);
      }
      
      res.json(result);
    } else {
      res.status(400).json(result);
    }
  } catch (error) {
    console.error('❌ Error adding MCP server:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Обновление сервера
app.put('/api/mcp/servers/:serverId', async (req, res) => {
  try {
    const { serverId } = req.params;
    const updates = req.body;

    const result = mcpConfig.updateServer(serverId, updates);

    if (result.success) {
      // Если сервер был отключен, отключаемся
      if (updates.enabled === false) {
        await mcpClient.disconnect(serverId);
      } else if (updates.enabled === true || (updates.enabled === undefined && result.server.enabled)) {
        // Если сервер включен, переподключаемся
        await mcpClient.disconnect(serverId);
        await mcpClient.connect(serverId, result.server.url);
      } else if (updates.url) {
        // Если изменился URL, переподключаемся
        await mcpClient.disconnect(serverId);
        if (result.server.enabled) {
          await mcpClient.connect(serverId, result.server.url);
        }
      }
      
      res.json(result);
    } else {
      res.status(400).json(result);
    }
  } catch (error) {
    console.error('❌ Error updating MCP server:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Удаление сервера
app.delete('/api/mcp/servers/:serverId', async (req, res) => {
  try {
    const { serverId } = req.params;

    // Отключаемся от сервера
    await mcpClient.disconnect(serverId);

    const result = mcpConfig.removeServer(serverId);
    
    if (result.success) {
      res.json(result);
    } else {
      res.status(400).json(result);
    }
  } catch (error) {
    console.error('❌ Error removing MCP server:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Тестирование подключения к серверу
app.post('/api/mcp/servers/:serverId/test', async (req, res) => {
  try {
    const { serverId } = req.params;
    const server = mcpConfig.getServer(serverId);

    if (!server) {
      return res.status(404).json({
        success: false,
        error: 'Сервер не найден',
      });
    }

    const result = await mcpClient.testConnection(server.url);
    res.json(result);
  } catch (error) {
    console.error('❌ Error testing MCP server:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Ручное подключение к серверу
app.post('/api/mcp/servers/:serverId/connect', async (req, res) => {
  try {
    const { serverId } = req.params;
    const server = mcpConfig.getServer(serverId);

    if (!server) {
      return res.status(404).json({
        success: false,
        error: 'Сервер не найден',
      });
    }

    const result = await mcpClient.connect(serverId, server.url);
    res.json(result);
  } catch (error) {
    console.error('❌ Error connecting to MCP server:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Отключение от сервера
app.post('/api/mcp/servers/:serverId/disconnect', async (req, res) => {
  try {
    const { serverId } = req.params;
    const result = await mcpClient.disconnect(serverId);
    res.json(result);
  } catch (error) {
    console.error('❌ Error disconnecting from MCP server:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Инициализация MCP подключений при старте сервера
async function initializeMCP() {
  try {
    console.log('🔌 Инициализация MCP подключений...');
    const results = await mcpClient.initializeConnections();
    
    results.forEach(result => {
      if (result.success) {
        console.log(`✅ Подключен к MCP серверу: ${result.serverName} (${result.serverId})`);
      } else {
        console.error(`❌ Ошибка подключения к ${result.serverName} (${result.serverId}): ${result.error}`);
      }
    });
  } catch (error) {
    console.error('❌ Ошибка инициализации MCP:', error);
  }
}

app.listen(PORT, async () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
  
  // Инициализируем MCP подключения после запуска сервера
  await initializeMCP();
});
