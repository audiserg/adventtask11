import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/message.dart';
import '../models/mcp_tool.dart';
import '../models/mcp_server.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ApiService _apiService;

  // Промпт для суммаризации контекста
  static const String _summarizationPrompt =
      'Суммаризируй кратко весь предыдущий контекст нашего разговора, сохранив ключевые темы, важные детали и контекст для продолжения диалога. Суммаризация должна быть краткой, но информативной.';

  ChatBloc({ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
      super(const ChatInitial()) {
    on<SendMessage>(_onSendMessage);
    on<ClearChat>(_onClearChat);
    on<UpdateTemperature>(_onUpdateTemperature);
    on<UpdateSystemPrompt>(_onUpdateSystemPrompt);
    on<LoadSettings>(_onLoadSettings);
    on<UpdateProvider>(_onUpdateProvider);
    on<UpdateModel>(_onUpdateModel);
    on<LoadModels>(_onLoadModels);
    on<DeleteMessage>(_onDeleteMessage);
    on<UpdateSummarizationThreshold>(_onUpdateSummarizationThreshold);
    on<ToggleMemory>(_onToggleMemory);
    on<ClearMemory>(_onClearMemory);
    on<LoadMcpTools>(_onLoadMcpTools);
    on<LoadMcpServers>(_onLoadMcpServers);
    on<CallMcpTool>(_onCallMcpTool);
    on<AddMcpServer>(_onAddMcpServer);
    on<UpdateMcpServer>(_onUpdateMcpServer);
    on<DeleteMcpServer>(_onDeleteMcpServer);
    on<TestMcpServer>(_onTestMcpServer);
    on<ConnectMcpServer>(_onConnectMcpServer);
    on<DisconnectMcpServer>(_onDisconnectMcpServer);

    // Загружаем настройки при инициализации
    _initializeSettings();
  }

  Future<void> _initializeSettings() async {
    // Небольшая задержка для инициализации SharedPreferences на веб-платформе
    await Future.delayed(const Duration(milliseconds: 100));
    add(const LoadSettings());
  }

  // Парсинг ответа в формате topic:<Тема>: body:<Ответ>: emotion:<Цвет>:
  Map<String, dynamic> _parseResponse(String response) {
    String? topic;
    String? body;
    Emotion? emotion;

    // Улучшенный парсинг: ищем паттерны topic:, body:, emotion:
    // Формат: topic:Тема: body:Ответ: emotion:Цвет:
    // Разделитель - двоеточие после значения, перед следующим ключевым словом

    final lowerResponse = response.toLowerCase();

    // Находим позиции всех ключевых слов
    final topicIndex = lowerResponse.indexOf('topic:');
    final bodyIndex = lowerResponse.indexOf('body:');
    final emotionIndex = lowerResponse.indexOf('emotion:');

    // Парсим topic: берем текст между "topic:" и следующим ключевым словом или концом
    if (topicIndex != -1) {
      final startPos = topicIndex + 6; // длина "topic:"
      // Определяем конец - следующее ключевое слово или конец строки
      int? endPos;
      if (bodyIndex != -1 && bodyIndex > topicIndex) {
        endPos = bodyIndex;
      } else if (emotionIndex != -1 && emotionIndex > topicIndex) {
        endPos = emotionIndex;
      }

      if (endPos != null) {
        // Берем текст между startPos и endPos, ищем последнее двоеточие как разделитель
        final textBetween = response.substring(startPos, endPos);
        final lastColon = textBetween.lastIndexOf(':');
        if (lastColon != -1) {
          topic = textBetween.substring(0, lastColon).trim();
        }
      } else {
        // Нет следующего ключевого слова, ищем последнее двоеточие в оставшемся тексте
        final remainingText = response.substring(startPos);
        final lastColon = remainingText.lastIndexOf(':');
        if (lastColon != -1) {
          topic = remainingText.substring(0, lastColon).trim();
        }
      }
    }

    // Парсим body: берем текст между "body:" и "emotion:" или концом
    if (bodyIndex != -1) {
      final startPos = bodyIndex + 5; // длина "body:"
      int? endPos;
      if (emotionIndex != -1 && emotionIndex > bodyIndex) {
        endPos = emotionIndex;
      }

      if (endPos != null) {
        final textBetween = response.substring(startPos, endPos);
        final lastColon = textBetween.lastIndexOf(':');
        if (lastColon != -1) {
          body = textBetween.substring(0, lastColon).trim();
        }
      } else {
        // Нет emotion, ищем последнее двоеточие в оставшемся тексте
        final remainingText = response.substring(startPos);
        final lastColon = remainingText.lastIndexOf(':');
        if (lastColon != -1) {
          body = remainingText.substring(0, lastColon).trim();
        } else {
          body = remainingText.trim();
        }
      }
    }

    // Парсим emotion: берем текст после "emotion:" до следующего двоеточия или конца
    if (emotionIndex != -1) {
      // Используем оригинальный response для извлечения, но lowerResponse для поиска
      final startPos = emotionIndex + 7; // длина "emotion:"
      final remainingText = response.substring(startPos);

      print('DEBUG: emotion found at index $emotionIndex');
      print('DEBUG: remaining text after emotion:: "$remainingText"');

      // Ищем двоеточие после emotion (разделитель)
      final colonPos = remainingText.indexOf(':');

      String emotionStr;
      if (colonPos != -1) {
        // Есть двоеточие - берем текст до него
        emotionStr = remainingText.substring(0, colonPos).trim().toUpperCase();
        print(
          'DEBUG: Found colon at position $colonPos, emotion string: "$emotionStr"',
        );
      } else {
        // Нет двоеточия - берем весь оставшийся текст (убираем пробелы и переносы строк)
        emotionStr = remainingText.trim().toUpperCase();
        // Убираем возможные переносы строк и лишние символы
        emotionStr = emotionStr.replaceAll(RegExp(r'[\n\r]+'), '');
        emotionStr = emotionStr
            .split(RegExp(r'[\s:]+'))
            .first; // Берем первое слово/значение
        print('DEBUG: No colon found, extracted emotion string: "$emotionStr"');
      }

      // Убираем все лишние символы, оставляем только буквы
      emotionStr = emotionStr.replaceAll(RegExp(r'[^A-Z]'), '');
      print('DEBUG: Final cleaned emotion string: "$emotionStr"');

      switch (emotionStr) {
        case 'GREEN':
          emotion = Emotion.green;
          print('DEBUG: ✓ Set emotion to GREEN');
          break;
        case 'BLUE':
          emotion = Emotion.blue;
          print('DEBUG: ✓ Set emotion to BLUE');
          break;
        case 'RED':
          emotion = Emotion.red;
          print('DEBUG: ✓ Set emotion to RED');
          break;
        default:
          print(
            'DEBUG: ✗ Unknown emotion value: "$emotionStr" (length: ${emotionStr.length})',
          );
          // Попробуем найти emotion в тексте другим способом
          final greenMatch = lowerResponse.contains('green');
          final blueMatch = lowerResponse.contains('blue');
          final redMatch = lowerResponse.contains('red');
          print(
            'DEBUG: Fallback check - green: $greenMatch, blue: $blueMatch, red: $redMatch',
          );
          if (greenMatch && !blueMatch && !redMatch) {
            emotion = Emotion.green;
            print('DEBUG: Fallback: Set emotion to GREEN');
          } else if (blueMatch && !greenMatch && !redMatch) {
            emotion = Emotion.blue;
            print('DEBUG: Fallback: Set emotion to BLUE');
          } else if (redMatch && !greenMatch && !blueMatch) {
            emotion = Emotion.red;
            print('DEBUG: Fallback: Set emotion to RED');
          }
      }
    } else {
      print('DEBUG: ✗ emotion: not found in response');
      print(
        'DEBUG: Response preview: ${response.substring(0, response.length > 200 ? 200 : response.length)}...',
      );
    }

    return {
      'topic': topic,
      'body': body ?? response, // Если body не найден, используем весь ответ
      'emotion': emotion,
      'originalText': response,
    };
  }

  Future<void> _onSendMessage(
    SendMessage event,
    Emitter<ChatState> emit,
  ) async {
    // Получаем текущие сообщения и тему
    final currentMessages = state is ChatLoaded
        ? (state as ChatLoaded).messages
        : state is ChatLoading
        ? (state as ChatLoading).messages
        : state is ChatError
        ? (state as ChatError).messages
        : <Message>[];

    final currentTopic = state is ChatLoaded
        ? (state as ChatLoaded).currentTopic
        : state is ChatLoading
        ? (state as ChatLoading).currentTopic
        : null;

    // Добавляем сообщение пользователя
    final userMessage = Message(text: event.message, isUser: true);
    final updatedMessages = [...currentMessages, userMessage];

    // Получаем текущие настройки
    final currentTemperature = state.temperature;
    final currentSystemPrompt = state.systemPrompt;

    // Получаем текущие настройки провайдера и модели
    final currentProvider = state.provider;
    final currentModel = state.model;
    final currentAvailableModels = state.availableModels;
    final currentSummarizationThreshold = state.summarizationThreshold;
    final currentUseMemory = state.useMemory;

    // Переходим в состояние загрузки
    emit(
      ChatLoading(
        updatedMessages,
        currentTopic: currentTopic,
        temperature: currentTemperature,
        systemPrompt: currentSystemPrompt,
        provider: currentProvider,
        model: currentModel,
        availableModels: currentAvailableModels,
        summarizationThreshold: currentSummarizationThreshold,
        useMemory: currentUseMemory,
      ),
    );

    try {
      // Получаем текущие настройки температуры и системного промпта
      final currentTemperature = state.temperature;
      final currentSystemPrompt = state.systemPrompt;
      final currentProvider = state.provider;
      final currentModel = state.model;
      final currentModelForApi = state.model.isNotEmpty ? state.model : null;

      // Получаем текущее состояние памяти
      final currentUseMemory = state.useMemory;

      // Отправляем запрос к API
      final responseData = await _apiService.sendMessage(
        updatedMessages,
        temperature: currentTemperature,
        systemPrompt: currentSystemPrompt.isNotEmpty
            ? currentSystemPrompt
            : null,
        provider: currentProvider,
        model: currentModelForApi,
        useMemory: currentUseMemory,
      );

      // Извлекаем текст ответа и информацию о токенах
      final response = responseData['content'] as String;
      final tokenUsage = responseData['tokenUsage'] as Map<String, dynamic>?;

      // Извлекаем информацию о LTM
      final ltmUsed = responseData['ltmUsed'] as bool?;
      final ltmEmpty = responseData['ltmEmpty'] as bool?;
      final ltmMessagesCount = responseData['ltmMessagesCount'] as int?;
      final ltmQuery = responseData['ltmQuery'] as String?;

      // Логируем информацию о LTM для отладки
      print('=== LTM DEBUG ===');
      print('ltmUsed: $ltmUsed (type: ${ltmUsed.runtimeType})');
      print('ltmEmpty: $ltmEmpty');
      print('ltmMessagesCount: $ltmMessagesCount');
      print('ltmQuery: $ltmQuery');
      print('================');

      if (ltmUsed == true) {
        print(
          'ChatBloc: LTM was used - ${ltmMessagesCount ?? 0} messages loaded for query: "$ltmQuery"',
        );
      } else if (ltmEmpty == true) {
        print(
          'ChatBloc: LTM search returned empty results for query: "$ltmQuery"',
        );
      }

      // Парсим ответ
      final parsed = _parseResponse(response);
      final topic = parsed['topic'] as String?;
      String body = parsed['body'] as String;
      final emotion = parsed['emotion'] as Emotion?;

      // Убираем "QUESTION:" из начала текста, если оно есть
      body = body
          .replaceFirst(RegExp(r'^QUESTION:\s*', caseSensitive: false), '')
          .trim();

      // Если body не распарсился (новый формат без topic:body:emotion:), используем весь ответ
      if (body.isEmpty || body == response) {
        body = response;
        // Убираем "QUESTION:" из начала, если есть
        body = body
            .replaceFirst(RegExp(r'^QUESTION:\s*', caseSensitive: false), '')
            .trim();
      }

      // Извлекаем информацию о токенах и контекстном окне
      int? promptTokens;
      int? completionTokens;
      int? totalTokens;
      bool? tokensEstimated;
      int? maxContextTokens;
      double? contextUsagePercent;

      if (tokenUsage != null) {
        promptTokens = tokenUsage['prompt_tokens'] as int?;
        completionTokens = tokenUsage['completion_tokens'] as int?;
        totalTokens = tokenUsage['total_tokens'] as int?;
        tokensEstimated = tokenUsage['estimated'] as bool?;
        maxContextTokens = tokenUsage['max_context_tokens'] as int?;
        if (tokenUsage['context_usage_percent'] != null) {
          contextUsagePercent = (tokenUsage['context_usage_percent'] as num)
              .toDouble();
        }
      }

      // Отладочный вывод (можно убрать в production)
      print('=== PARSING DEBUG ===');
      print('Original response: $response');
      print('Parsed topic: $topic');
      print('Parsed body length: ${body.length}');
      print('Parsed emotion: $emotion');
      print('Token usage: $tokenUsage');
      print('Emotion type: ${emotion.runtimeType}');
      print('Emotion is null: ${emotion == null}');
      if (emotion != null) {
        print('Emotion value: ${emotion.toString()}');
      }
      print('===================');

      // Добавляем ответ от ИИ
      final aiMessage = Message(
        text: response,
        isUser: false,
        topic: topic,
        body: body,
        emotion: emotion,
        temperature: currentTemperature,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
        tokensEstimated: tokensEstimated,
        maxContextTokens: maxContextTokens,
        contextUsagePercent: contextUsagePercent,
        ltmUsed: ltmUsed,
        ltmMessagesCount: ltmMessagesCount,
        ltmQuery: ltmQuery,
      );

      print('=== MESSAGE CREATION DEBUG ===');
      print('Created message with emotion: ${aiMessage.emotion}');
      print('Message emotion is null: ${aiMessage.emotion == null}');
      print('Message emotion type: ${aiMessage.emotion.runtimeType}');
      print('Message has topic: ${aiMessage.topic != null}');
      print('Message has body: ${aiMessage.body != null}');
      print('Message ltmUsed: ${aiMessage.ltmUsed}');
      print('Message ltmMessagesCount: ${aiMessage.ltmMessagesCount}');
      print('Message ltmQuery: ${aiMessage.ltmQuery}');
      print('==============================');

      final finalMessages = [...updatedMessages, aiMessage];

      // Проверяем, нужно ли суммаризировать контекст
      if (totalTokens != null && totalTokens > currentSummarizationThreshold) {
        print(
          'ChatBloc: Превышен порог токенов ($totalTokens > $currentSummarizationThreshold), запускаем суммаризацию',
        );
        try {
          await _summarizeContext(
            finalMessages,
            emit,
            currentTemperature,
            currentSystemPrompt,
            currentProvider,
            currentModel,
            currentAvailableModels,
            currentSummarizationThreshold,
          );
          return; // _summarizeContext уже обновил состояние
        } catch (e) {
          print('ChatBloc: Ошибка при суммаризации контекста: $e');
          // Продолжаем с текущим контекстом при ошибке суммаризации
        }
      }

      // Переходим в состояние загружено с темой
      emit(
        ChatLoaded(
          finalMessages,
          currentTopic: topic,
          ltmUsed: ltmUsed,
          ltmEmpty: ltmEmpty,
          ltmMessagesCount: ltmMessagesCount,
          ltmQuery: ltmQuery,
          temperature: currentTemperature,
          systemPrompt: currentSystemPrompt,
          provider: currentProvider,
          model: currentModel,
          availableModels: currentAvailableModels,
          summarizationThreshold: currentSummarizationThreshold,
          useMemory: currentUseMemory,
        ),
      );
    } catch (e) {
      // Переходим в состояние ошибки
      String errorMessage = e.toString();

      // Убираем префикс "Exception: " если есть
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      }

      if (errorMessage.contains('Превышен дневной лимит') ||
          errorMessage.contains('Daily limit exceeded')) {
        // Ошибка лимита - оставляем сообщение как есть
        errorMessage = errorMessage;
      } else if (errorMessage.contains('Failed host lookup') ||
          errorMessage.contains('Connection refused')) {
        errorMessage =
            'Не удалось подключиться к серверу. Убедитесь, что бэкенд запущен на порту 3000.';
      } else if (errorMessage.contains('timeout')) {
        errorMessage = 'Превышено время ожидания ответа от сервера.';
      } else if (errorMessage.contains('500') ||
          errorMessage.contains('Server configuration')) {
        errorMessage =
            'Ошибка сервера. Проверьте настройку API ключа в .env файле.';
      }
      emit(
        ChatError(
          updatedMessages,
          errorMessage,
          temperature: currentTemperature,
          systemPrompt: currentSystemPrompt,
          provider: currentProvider,
          model: currentModel,
          availableModels: currentAvailableModels,
          summarizationThreshold: currentSummarizationThreshold,
          useMemory: currentUseMemory,
        ),
      );
    }
  }

  void _onClearChat(ClearChat event, Emitter<ChatState> emit) {
    emit(
      ChatInitial(
        temperature: state.temperature,
        systemPrompt: state.systemPrompt,
        provider: state.provider,
        model: state.model,
        availableModels: state.availableModels,
        summarizationThreshold: state.summarizationThreshold,
        useMemory: state.useMemory,
      ),
    );
  }

  void _onUpdateTemperature(
    UpdateTemperature event,
    Emitter<ChatState> emit,
  ) async {
    print('ChatBloc: Обновление температуры на ${event.temperature}');
    // Сохраняем настройку
    final saved = await SettingsService.saveTemperature(event.temperature);
    print('ChatBloc: Температура сохранена: $saved');

    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      emit(
        ChatLoaded(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: event.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: currentState.useMemory,
        ),
      );
    } else if (state is ChatLoading) {
      final currentState = state as ChatLoading;
      emit(
        ChatLoading(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: event.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: currentState.useMemory,
        ),
      );
    } else if (state is ChatError) {
      final currentState = state as ChatError;
      emit(
        ChatError(
          currentState.messages,
          currentState.error,
          temperature: event.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: currentState.useMemory,
        ),
      );
    } else {
      emit(
        ChatInitial(
          temperature: event.temperature,
          systemPrompt: state.systemPrompt,
          provider: state.provider,
          model: state.model,
          availableModels: state.availableModels,
          summarizationThreshold: state.summarizationThreshold,
          useMemory: state.useMemory,
        ),
      );
    }
  }

  void _onUpdateSystemPrompt(
    UpdateSystemPrompt event,
    Emitter<ChatState> emit,
  ) async {
    print(
      'ChatBloc: Обновление системного промпта (длина: ${event.systemPrompt.length})',
    );
    // Сохраняем настройку
    final saved = await SettingsService.saveSystemPrompt(event.systemPrompt);
    print('ChatBloc: Системный промпт сохранен: $saved');

    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      emit(
        ChatLoaded(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: currentState.temperature,
          systemPrompt: event.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
        ),
      );
    } else if (state is ChatLoading) {
      final currentState = state as ChatLoading;
      emit(
        ChatLoading(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: currentState.temperature,
          systemPrompt: event.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: currentState.useMemory,
        ),
      );
    } else if (state is ChatError) {
      final currentState = state as ChatError;
      emit(
        ChatError(
          currentState.messages,
          currentState.error,
          temperature: currentState.temperature,
          systemPrompt: event.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: currentState.useMemory,
        ),
      );
    } else {
      emit(
        ChatInitial(
          temperature: state.temperature,
          systemPrompt: event.systemPrompt,
          provider: state.provider,
          model: state.model,
          availableModels: state.availableModels,
          summarizationThreshold: state.summarizationThreshold,
          useMemory: state.useMemory,
        ),
      );
    }
  }

  void _onLoadSettings(LoadSettings event, Emitter<ChatState> emit) async {
    final settings = await SettingsService.loadAllSettings();
    final temperature = settings['temperature'] as double;
    final systemPrompt = settings['systemPrompt'] as String;
    final provider = settings['provider'] as String? ?? 'deepseek';
    final model = settings['model'] as String? ?? '';
    final summarizationThreshold =
        settings['summarizationThreshold'] as int? ?? 1000;
    final useMemory = settings['useMemory'] as bool? ?? false;

    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      emit(
        ChatLoaded(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: temperature,
          systemPrompt: systemPrompt,
          provider: provider,
          model: model,
          availableModels: currentState.availableModels,
          summarizationThreshold: summarizationThreshold,
          useMemory: useMemory,
        ),
      );
    } else if (state is ChatLoading) {
      final currentState = state as ChatLoading;
      emit(
        ChatLoading(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: temperature,
          systemPrompt: systemPrompt,
          provider: provider,
          model: model,
          availableModels: currentState.availableModels,
          summarizationThreshold: summarizationThreshold,
          useMemory: useMemory,
        ),
      );
    } else if (state is ChatError) {
      final currentState = state as ChatError;
      emit(
        ChatError(
          currentState.messages,
          currentState.error,
          temperature: temperature,
          systemPrompt: systemPrompt,
          provider: provider,
          model: model,
          availableModels: currentState.availableModels,
          summarizationThreshold: summarizationThreshold,
          useMemory: useMemory,
        ),
      );
    } else {
      emit(
        ChatInitial(
          temperature: temperature,
          systemPrompt: systemPrompt,
          provider: provider,
          model: model,
          availableModels: state.availableModels,
          summarizationThreshold: summarizationThreshold,
          useMemory: useMemory,
        ),
      );
    }
  }

  void _onUpdateProvider(UpdateProvider event, Emitter<ChatState> emit) async {
    print('ChatBloc: Обновление провайдера на ${event.provider}');
    // Сохраняем настройку
    final saved = await SettingsService.saveProvider(event.provider);
    print('ChatBloc: Провайдер сохранен: $saved');

    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      emit(
        ChatLoaded(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: event.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
        ),
      );
    } else if (state is ChatLoading) {
      final currentState = state as ChatLoading;
      emit(
        ChatLoading(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: event.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: currentState.useMemory,
        ),
      );
    } else if (state is ChatError) {
      final currentState = state as ChatError;
      emit(
        ChatError(
          currentState.messages,
          currentState.error,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: event.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: currentState.useMemory,
        ),
      );
    } else {
      emit(
        ChatInitial(
          temperature: state.temperature,
          systemPrompt: state.systemPrompt,
          provider: event.provider,
          model: state.model,
          availableModels: state.availableModels,
          summarizationThreshold: state.summarizationThreshold,
          useMemory: state.useMemory,
        ),
      );
    }
  }

  void _onUpdateModel(UpdateModel event, Emitter<ChatState> emit) async {
    print('ChatBloc: Обновление модели на ${event.model}');
    // Сохраняем настройку
    final saved = await SettingsService.saveModel(event.model);
    print('ChatBloc: Модель сохранена: $saved');

    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      emit(
        ChatLoaded(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: event.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
        ),
      );
    } else if (state is ChatLoading) {
      final currentState = state as ChatLoading;
      emit(
        ChatLoading(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: event.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: currentState.useMemory,
        ),
      );
    } else if (state is ChatError) {
      final currentState = state as ChatError;
      emit(
        ChatError(
          currentState.messages,
          currentState.error,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: event.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: currentState.useMemory,
        ),
      );
    } else {
      emit(
        ChatInitial(
          temperature: state.temperature,
          systemPrompt: state.systemPrompt,
          provider: state.provider,
          model: event.model,
          availableModels: state.availableModels,
          summarizationThreshold: state.summarizationThreshold,
          useMemory: state.useMemory,
        ),
      );
    }
  }

  void _onUpdateSummarizationThreshold(
    UpdateSummarizationThreshold event,
    Emitter<ChatState> emit,
  ) async {
    print('ChatBloc: Обновление порога суммаризации на ${event.threshold}');
    // Сохраняем настройку
    final saved = await SettingsService.saveSummarizationThreshold(
      event.threshold,
    );
    print('ChatBloc: Порог суммаризации сохранен: $saved');

    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      emit(
        ChatLoaded(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: event.threshold,
        ),
      );
    } else if (state is ChatLoading) {
      final currentState = state as ChatLoading;
      emit(
        ChatLoading(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: event.threshold,
          useMemory: currentState.useMemory,
        ),
      );
    } else if (state is ChatError) {
      final currentState = state as ChatError;
      emit(
        ChatError(
          currentState.messages,
          currentState.error,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: event.threshold,
          useMemory: currentState.useMemory,
        ),
      );
    } else {
      emit(
        ChatInitial(
          temperature: state.temperature,
          systemPrompt: state.systemPrompt,
          provider: state.provider,
          model: state.model,
          availableModels: state.availableModels,
          summarizationThreshold: event.threshold,
          useMemory: state.useMemory,
        ),
      );
    }
  }

  void _onLoadModels(LoadModels event, Emitter<ChatState> emit) async {
    try {
      print('ChatBloc: Загрузка списка моделей...');
      final modelsData = await _apiService.getAvailableModels();
      print('ChatBloc: Список моделей загружен');

      if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;
        emit(
          ChatLoaded(
            currentState.messages,
            currentTopic: currentState.currentTopic,
            temperature: currentState.temperature,
            systemPrompt: currentState.systemPrompt,
            provider: currentState.provider,
            model: currentState.model,
            availableModels: modelsData,
            summarizationThreshold: currentState.summarizationThreshold,
            useMemory: currentState.useMemory,
          ),
        );
      } else if (state is ChatLoading) {
        final currentState = state as ChatLoading;
        emit(
          ChatLoading(
            currentState.messages,
            currentTopic: currentState.currentTopic,
            temperature: currentState.temperature,
            systemPrompt: currentState.systemPrompt,
            provider: currentState.provider,
            model: currentState.model,
            availableModels: modelsData,
            summarizationThreshold: currentState.summarizationThreshold,
            useMemory: currentState.useMemory,
          ),
        );
      } else if (state is ChatError) {
        final currentState = state as ChatError;
        emit(
          ChatError(
            currentState.messages,
            currentState.error,
            temperature: currentState.temperature,
            systemPrompt: currentState.systemPrompt,
            provider: currentState.provider,
            model: currentState.model,
            availableModels: modelsData,
            summarizationThreshold: currentState.summarizationThreshold,
            useMemory: currentState.useMemory,
          ),
        );
      } else {
        emit(
          ChatInitial(
            temperature: state.temperature,
            systemPrompt: state.systemPrompt,
            provider: state.provider,
            model: state.model,
            availableModels: modelsData,
            summarizationThreshold: state.summarizationThreshold,
            useMemory: state.useMemory,
          ),
        );
      }
    } catch (e) {
      print('ChatBloc: Ошибка при загрузке списка моделей: $e');
      // Не меняем состояние при ошибке загрузки моделей
    }
  }

  void _onDeleteMessage(DeleteMessage event, Emitter<ChatState> emit) {
    // Получаем текущие сообщения
    List<Message> currentMessages = [];
    String? currentTopic;

    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      currentMessages = currentState.messages;
      currentTopic = currentState.currentTopic;
    } else if (state is ChatLoading) {
      final currentState = state as ChatLoading;
      currentMessages = currentState.messages;
      currentTopic = currentState.currentTopic;
    } else if (state is ChatError) {
      final currentState = state as ChatError;
      currentMessages = currentState.messages;
      currentTopic = null;
    }

    // Проверяем, что индекс валидный
    if (event.messageIndex >= 0 &&
        event.messageIndex < currentMessages.length) {
      // Удаляем сообщение
      final updatedMessages = List<Message>.from(currentMessages);
      updatedMessages.removeAt(event.messageIndex);

      // Обновляем состояние
      if (state is ChatLoaded) {
        emit(
          ChatLoaded(
            updatedMessages,
            currentTopic: currentTopic,
            temperature: state.temperature,
            systemPrompt: state.systemPrompt,
            provider: state.provider,
            model: state.model,
            availableModels: state.availableModels,
            summarizationThreshold: state.summarizationThreshold,
            useMemory: state.useMemory,
          ),
        );
      } else if (state is ChatLoading) {
        emit(
          ChatLoading(
            updatedMessages,
            currentTopic: currentTopic,
            temperature: state.temperature,
            systemPrompt: state.systemPrompt,
            provider: state.provider,
            model: state.model,
            availableModels: state.availableModels,
            summarizationThreshold: state.summarizationThreshold,
            useMemory: state.useMemory,
          ),
        );
      } else if (state is ChatError) {
        emit(
          ChatError(
            updatedMessages,
            (state as ChatError).error,
            temperature: state.temperature,
            systemPrompt: state.systemPrompt,
            provider: state.provider,
            model: state.model,
            availableModels: state.availableModels,
            summarizationThreshold: state.summarizationThreshold,
            useMemory: state.useMemory,
          ),
        );
      } else {
        emit(
          ChatInitial(
            temperature: state.temperature,
            systemPrompt: state.systemPrompt,
            provider: state.provider,
            model: state.model,
            availableModels: state.availableModels,
            summarizationThreshold: state.summarizationThreshold,
            useMemory: state.useMemory,
          ),
        );
      }
    }
  }

  // Суммаризация контекста
  Future<void> _summarizeContext(
    List<Message> messages,
    Emitter<ChatState> emit,
    double temperature,
    String systemPrompt,
    String provider,
    String model,
    Map<String, dynamic>? availableModels,
    int summarizationThreshold,
  ) async {
    try {
      print(
        'ChatBloc: Начинаем суммаризацию контекста (${messages.length} сообщений)',
      );

      // Всегда используем только текущий контекст чата для суммаризации
      final contextText = messages
          .map(
            (msg) =>
                '${msg.isUser ? "Пользователь" : "Ассистент"}: ${msg.text}',
          )
          .join('\n\n');

      String summarizationRequest;

      // Если включена память, получаем min/max ID из БД для промпта
      if (state.useMemory) {
        try {
          print(
            'ChatBloc: Получение диапазона ID из памяти для суммаризации...',
          );
          final memoryMessages = await _apiService.getAllMemoryMessages();

          if (memoryMessages.isNotEmpty) {
            // Определяем минимальный и максимальный ID
            final ids = memoryMessages.map((msg) => msg['id'] as int).toList()
              ..sort();
            final minId = ids.first;
            final maxId = ids.last;

            print('ChatBloc: Диапазон ID в памяти: $minId - $maxId');

            summarizationRequest =
                '$_summarizationPrompt\n\n' +
                'ВАЖНО: В конце суммаризации обязательно укажи диапазон ID сообщений в формате **search**(<n>,<m>), ' +
                'где n - ID первого сообщения в базе данных ($minId), m - ID последнего сообщения в базе данных ($maxId).\n\n' +
                'Контекст разговора:\n$contextText';
          } else {
            // Если нет сообщений в памяти, используем обычную суммаризацию
            summarizationRequest =
                '$_summarizationPrompt\n\nКонтекст разговора:\n$contextText';
          }
        } catch (e) {
          print('ChatBloc: Ошибка при получении диапазона ID из памяти: $e');
          // Fallback к обычной суммаризации
          summarizationRequest =
              '$_summarizationPrompt\n\nКонтекст разговора:\n$contextText';
        }
      } else {
        // Обычная суммаризация без памяти
        summarizationRequest =
            '$_summarizationPrompt\n\nКонтекст разговора:\n$contextText';
      }

      // Создаем сообщение для суммаризации с флагом isSummarization
      final summarizationMessages = [
        Message(
          text: summarizationRequest,
          isUser: true,
          isSummarization:
              true, // Помечаем как суммаризацию, чтобы ответ не сохранялся в LTM
        ),
      ];

      // Отправляем запрос на суммаризацию
      final responseData = await _apiService.sendMessage(
        summarizationMessages,
        temperature: temperature,
        systemPrompt: systemPrompt.isNotEmpty ? systemPrompt : null,
        provider: provider,
        model: model.isNotEmpty ? model : null,
      );

      // Извлекаем текст суммаризации
      final summarizationText = responseData['content'] as String;

      print(
        'ChatBloc: Получена суммаризация (${summarizationText.length} символов)',
      );

      // Парсим ответ суммаризации
      final parsed = _parseResponse(summarizationText);
      final topic = parsed['topic'] as String?;
      String body = parsed['body'] as String;
      final emotion = parsed['emotion'] as Emotion?;

      // Убираем "QUESTION:" из начала текста, если оно есть
      body = body
          .replaceFirst(RegExp(r'^QUESTION:\s*', caseSensitive: false), '')
          .trim();

      // Если body не распарсился, используем весь ответ
      if (body.isEmpty || body == summarizationText) {
        body = summarizationText;
        body = body
            .replaceFirst(RegExp(r'^QUESTION:\s*', caseSensitive: false), '')
            .trim();
      }

      // Создаем сообщение с суммаризацией
      final summarizationMessage = Message(
        text: summarizationText,
        isUser: false,
        topic: topic,
        body: body,
        emotion: emotion,
        temperature: temperature,
        isSummarization: true,
      );

      // НЕ сохраняем суммаризацию в память - суммаризации исключены из LTM
      // Суммаризации не должны попадать в долгосрочную память
      if (state.useMemory) {
        print(
          'ChatBloc: Суммаризация не сохраняется в LTM (исключена из долгосрочной памяти)',
        );
      }

      // Находим последний запрос пользователя и последний ответ модели
      Message? lastUserMessage;
      Message? lastAssistantMessage;

      // Ищем с конца списка
      for (int i = messages.length - 1; i >= 0; i--) {
        if (lastUserMessage == null && messages[i].isUser) {
          lastUserMessage = messages[i];
        }
        if (lastAssistantMessage == null && !messages[i].isUser) {
          lastAssistantMessage = messages[i];
        }
        // Если нашли оба, можно выйти
        if (lastUserMessage != null && lastAssistantMessage != null) {
          break;
        }
      }

      // Формируем список сообщений: последний запрос + последний ответ + суммаризация
      final summarizedMessages = <Message>[];

      // Добавляем последний запрос пользователя, если он есть
      if (lastUserMessage != null) {
        summarizedMessages.add(lastUserMessage);
      }

      // Добавляем последний ответ модели, если он есть
      if (lastAssistantMessage != null) {
        summarizedMessages.add(lastAssistantMessage);
      }

      // Добавляем суммаризацию в конце (будет отображаться мелким шрифтом)
      summarizedMessages.add(summarizationMessage);

      print(
        'ChatBloc: Контекст суммаризирован. Старых сообщений: ${messages.length}, после суммаризации: ${summarizedMessages.length} (последний запрос + последний ответ + суммаризация)',
      );

      // Обновляем состояние с суммаризацией
      emit(
        ChatLoaded(
          summarizedMessages,
          currentTopic: topic,
          temperature: temperature,
          systemPrompt: systemPrompt,
          provider: provider,
          model: model,
          availableModels: availableModels,
          summarizationThreshold: summarizationThreshold,
          useMemory: state.useMemory,
        ),
      );
    } catch (e) {
      print('ChatBloc: Ошибка при суммаризации контекста: $e');
      rethrow; // Пробрасываем ошибку, чтобы _onSendMessage мог обработать её
    }
  }

  void _onToggleMemory(ToggleMemory event, Emitter<ChatState> emit) async {
    print('ChatBloc: Переключение памяти на ${event.enabled}');
    // Сохраняем настройку
    final saved = await SettingsService.saveUseMemory(event.enabled);
    print('ChatBloc: Состояние памяти сохранено: $saved');

    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      emit(
        ChatLoaded(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: event.enabled,
        ),
      );
    } else if (state is ChatLoading) {
      final currentState = state as ChatLoading;
      emit(
        ChatLoading(
          currentState.messages,
          currentTopic: currentState.currentTopic,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: event.enabled,
        ),
      );
    } else if (state is ChatError) {
      final currentState = state as ChatError;
      emit(
        ChatError(
          currentState.messages,
          currentState.error,
          temperature: currentState.temperature,
          systemPrompt: currentState.systemPrompt,
          provider: currentState.provider,
          model: currentState.model,
          availableModels: currentState.availableModels,
          summarizationThreshold: currentState.summarizationThreshold,
          useMemory: event.enabled,
        ),
      );
    } else {
      emit(
        ChatInitial(
          temperature: state.temperature,
          systemPrompt: state.systemPrompt,
          provider: state.provider,
          model: state.model,
          availableModels: state.availableModels,
          summarizationThreshold: state.summarizationThreshold,
          useMemory: event.enabled,
        ),
      );
    }
  }

  Future<void> _onClearMemory(
    ClearMemory event,
    Emitter<ChatState> emit,
  ) async {
    try {
      print('ChatBloc: Очистка памяти...');
      final success = await _apiService.clearMemory();

      if (success) {
        print('ChatBloc: Память успешно очищена');
      } else {
        print('ChatBloc: Ошибка при очистке памяти - операция не выполнена');
        throw Exception('Не удалось очистить память');
      }

      // Обновляем состояние
      if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;
        emit(
          ChatLoaded(
            currentState.messages,
            currentTopic: currentState.currentTopic,
            temperature: currentState.temperature,
            systemPrompt: currentState.systemPrompt,
            provider: currentState.provider,
            model: currentState.model,
            availableModels: currentState.availableModels,
            summarizationThreshold: currentState.summarizationThreshold,
            useMemory: currentState.useMemory,
          ),
        );
      } else if (state is ChatLoading) {
        final currentState = state as ChatLoading;
        emit(
          ChatLoading(
            currentState.messages,
            currentTopic: currentState.currentTopic,
            temperature: currentState.temperature,
            systemPrompt: currentState.systemPrompt,
            provider: currentState.provider,
            model: currentState.model,
            availableModels: currentState.availableModels,
            summarizationThreshold: currentState.summarizationThreshold,
            useMemory: currentState.useMemory,
          ),
        );
      } else if (state is ChatError) {
        final currentState = state as ChatError;
        emit(
          ChatError(
            currentState.messages,
            currentState.error,
            temperature: currentState.temperature,
            systemPrompt: currentState.systemPrompt,
            provider: currentState.provider,
            model: currentState.model,
            availableModels: currentState.availableModels,
            summarizationThreshold: currentState.summarizationThreshold,
            useMemory: currentState.useMemory,
          ),
        );
      }
    } catch (e) {
      print('ChatBloc: Ошибка при очистке памяти: $e');
      rethrow; // Пробрасываем ошибку, чтобы UI мог показать сообщение
    }
  }

  // Получить текущую тему из состояния
  String? getCurrentTopic() {
    if (state is ChatLoaded) {
      return (state as ChatLoaded).currentTopic;
    } else if (state is ChatLoading) {
      return (state as ChatLoading).currentTopic;
    }
    return null;
  }

  // MCP обработчики
  Future<void> _onLoadMcpTools(
    LoadMcpTools event,
    Emitter<ChatState> emit,
  ) async {
    try {
      emit(_copyStateWith(mcpToolsLoading: true, mcpError: null));

      final tools = await _apiService.getMcpTools(serverId: event.serverId);

      emit(
        _copyStateWith(mcpTools: tools, mcpToolsLoading: false, mcpError: null),
      );
    } catch (e) {
      emit(_copyStateWith(mcpToolsLoading: false, mcpError: e.toString()));
    }
  }

  Future<void> _onLoadMcpServers(
    LoadMcpServers event,
    Emitter<ChatState> emit,
  ) async {
    try {
      emit(_copyStateWith(mcpToolsLoading: true, mcpError: null));

      final servers = await _apiService.getMcpServers();

      emit(
        _copyStateWith(
          mcpServers: servers,
          mcpToolsLoading: false,
          mcpError: null,
        ),
      );
    } catch (e) {
      emit(_copyStateWith(mcpToolsLoading: false, mcpError: e.toString()));
    }
  }

  Future<void> _onCallMcpTool(
    CallMcpTool event,
    Emitter<ChatState> emit,
  ) async {
    try {
      emit(_copyStateWith(mcpToolsLoading: true, mcpError: null));

      final result = await _apiService.callMcpTool(
        event.toolName,
        event.serverId,
        event.args,
      );

      emit(_copyStateWith(mcpToolsLoading: false, mcpError: null));

      // Можно добавить логику для отображения результата
      print('MCP Tool result: $result');
    } catch (e) {
      emit(_copyStateWith(mcpToolsLoading: false, mcpError: e.toString()));
    }
  }

  Future<void> _onAddMcpServer(
    AddMcpServer event,
    Emitter<ChatState> emit,
  ) async {
    try {
      emit(_copyStateWith(mcpToolsLoading: true, mcpError: null));

      final server = await _apiService.addMcpServer(
        id: event.id,
        name: event.name,
        url: event.url,
        enabled: event.enabled,
        description: event.description,
      );

      // Обновляем список серверов
      final servers = await _apiService.getMcpServers();

      emit(
        _copyStateWith(
          mcpServers: servers,
          mcpToolsLoading: false,
          mcpError: null,
        ),
      );
    } catch (e) {
      emit(_copyStateWith(mcpToolsLoading: false, mcpError: e.toString()));
    }
  }

  Future<void> _onUpdateMcpServer(
    UpdateMcpServer event,
    Emitter<ChatState> emit,
  ) async {
    try {
      emit(_copyStateWith(mcpToolsLoading: true, mcpError: null));

      await _apiService.updateMcpServer(event.serverId, event.updates);

      // Обновляем список серверов
      final servers = await _apiService.getMcpServers();

      emit(
        _copyStateWith(
          mcpServers: servers,
          mcpToolsLoading: false,
          mcpError: null,
        ),
      );
    } catch (e) {
      emit(_copyStateWith(mcpToolsLoading: false, mcpError: e.toString()));
    }
  }

  Future<void> _onDeleteMcpServer(
    DeleteMcpServer event,
    Emitter<ChatState> emit,
  ) async {
    try {
      emit(_copyStateWith(mcpToolsLoading: true, mcpError: null));

      await _apiService.deleteMcpServer(event.serverId);

      // Обновляем список серверов
      final servers = await _apiService.getMcpServers();

      emit(
        _copyStateWith(
          mcpServers: servers,
          mcpToolsLoading: false,
          mcpError: null,
        ),
      );
    } catch (e) {
      emit(_copyStateWith(mcpToolsLoading: false, mcpError: e.toString()));
    }
  }

  Future<void> _onTestMcpServer(
    TestMcpServer event,
    Emitter<ChatState> emit,
  ) async {
    try {
      emit(_copyStateWith(mcpToolsLoading: true, mcpError: null));

      final result = await _apiService.testMcpServer(event.serverId);

      emit(
        _copyStateWith(
          mcpToolsLoading: false,
          mcpError: result['success'] == true
              ? null
              : result['error']?.toString(),
        ),
      );
    } catch (e) {
      emit(_copyStateWith(mcpToolsLoading: false, mcpError: e.toString()));
    }
  }

  Future<void> _onConnectMcpServer(
    ConnectMcpServer event,
    Emitter<ChatState> emit,
  ) async {
    try {
      emit(_copyStateWith(mcpToolsLoading: true, mcpError: null));

      await _apiService.connectMcpServer(event.serverId);

      // Обновляем список серверов
      final servers = await _apiService.getMcpServers();

      emit(
        _copyStateWith(
          mcpServers: servers,
          mcpToolsLoading: false,
          mcpError: null,
        ),
      );
    } catch (e) {
      emit(_copyStateWith(mcpToolsLoading: false, mcpError: e.toString()));
    }
  }

  Future<void> _onDisconnectMcpServer(
    DisconnectMcpServer event,
    Emitter<ChatState> emit,
  ) async {
    try {
      emit(_copyStateWith(mcpToolsLoading: true, mcpError: null));

      await _apiService.disconnectMcpServer(event.serverId);

      // Обновляем список серверов
      final servers = await _apiService.getMcpServers();

      emit(
        _copyStateWith(
          mcpServers: servers,
          mcpToolsLoading: false,
          mcpError: null,
        ),
      );
    } catch (e) {
      emit(_copyStateWith(mcpToolsLoading: false, mcpError: e.toString()));
    }
  }

  // Вспомогательный метод для копирования состояния с новыми значениями MCP
  ChatState _copyStateWith({
    List<McpTool>? mcpTools,
    List<McpServer>? mcpServers,
    bool? mcpToolsLoading,
    String? mcpError,
  }) {
    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      return ChatLoaded(
        currentState.messages,
        currentTopic: currentState.currentTopic,
        ltmUsed: currentState.ltmUsed,
        ltmEmpty: currentState.ltmEmpty,
        ltmMessagesCount: currentState.ltmMessagesCount,
        ltmQuery: currentState.ltmQuery,
        temperature: currentState.temperature,
        systemPrompt: currentState.systemPrompt,
        provider: currentState.provider,
        model: currentState.model,
        availableModels: currentState.availableModels,
        summarizationThreshold: currentState.summarizationThreshold,
        useMemory: currentState.useMemory,
        mcpTools: mcpTools ?? currentState.mcpTools,
        mcpServers: mcpServers ?? currentState.mcpServers,
        mcpToolsLoading: mcpToolsLoading ?? currentState.mcpToolsLoading,
        mcpError: mcpError ?? currentState.mcpError,
      );
    } else if (state is ChatLoading) {
      final currentState = state as ChatLoading;
      return ChatLoading(
        currentState.messages,
        currentTopic: currentState.currentTopic,
        temperature: currentState.temperature,
        systemPrompt: currentState.systemPrompt,
        provider: currentState.provider,
        model: currentState.model,
        availableModels: currentState.availableModels,
        summarizationThreshold: currentState.summarizationThreshold,
        useMemory: currentState.useMemory,
        mcpTools: mcpTools ?? currentState.mcpTools,
        mcpServers: mcpServers ?? currentState.mcpServers,
        mcpToolsLoading: mcpToolsLoading ?? currentState.mcpToolsLoading,
        mcpError: mcpError ?? currentState.mcpError,
      );
    } else if (state is ChatError) {
      final currentState = state as ChatError;
      return ChatError(
        currentState.messages,
        currentState.error,
        temperature: currentState.temperature,
        systemPrompt: currentState.systemPrompt,
        provider: currentState.provider,
        model: currentState.model,
        availableModels: currentState.availableModels,
        summarizationThreshold: currentState.summarizationThreshold,
        useMemory: currentState.useMemory,
        mcpTools: mcpTools ?? currentState.mcpTools,
        mcpServers: mcpServers ?? currentState.mcpServers,
        mcpToolsLoading: mcpToolsLoading ?? currentState.mcpToolsLoading,
        mcpError: mcpError ?? currentState.mcpError,
      );
    } else {
      // ChatInitial
      return ChatInitial(
        temperature: state.temperature,
        systemPrompt: state.systemPrompt,
        provider: state.provider,
        model: state.model,
        availableModels: state.availableModels,
        summarizationThreshold: state.summarizationThreshold,
        useMemory: state.useMemory,
        mcpTools: mcpTools ?? state.mcpTools,
        mcpServers: mcpServers ?? state.mcpServers,
        mcpToolsLoading: mcpToolsLoading ?? state.mcpToolsLoading,
        mcpError: mcpError ?? state.mcpError,
      );
    }
  }
}
