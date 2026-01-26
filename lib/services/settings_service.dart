import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _temperatureKey = 'temperature';
  static const String _systemPromptKey = 'system_prompt';
  static const String _providerKey = 'provider';
  static const String _modelKey = 'model';
  static const String _summarizationThresholdKey = 'summarization_threshold';
  static const double _defaultTemperature = 0.7;
  static const String _defaultSystemPrompt = '';
  static const String _defaultProvider = 'deepseek';
  static const String _defaultModel = '';
  static const int _defaultSummarizationThreshold = 1000;
  static const String _useMemoryKey = 'use_memory';
  static const bool _defaultUseMemory = false;

  // Загрузить температуру
  static Future<double> loadTemperature() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getDouble(_temperatureKey) ?? _defaultTemperature;
      print('SettingsService: Загружена температура: $value');
      return value;
    } catch (e) {
      print('SettingsService: Ошибка при загрузке температуры: $e');
      return _defaultTemperature;
    }
  }

  // Сохранить температуру
  static Future<bool> saveTemperature(double temperature) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = await prefs.setDouble(_temperatureKey, temperature);
      print('SettingsService: Сохранена температура $temperature, результат: $result');
      // Дополнительная проверка - читаем обратно
      final verify = prefs.getDouble(_temperatureKey);
      print('SettingsService: Проверка сохранения - прочитано: $verify');
      return result;
    } catch (e, stackTrace) {
      print('SettingsService: Ошибка при сохранении температуры: $e');
      print('SettingsService: Stack trace: $stackTrace');
      return false;
    }
  }

  // Загрузить системный промпт
  static Future<String> loadSystemPrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_systemPromptKey) ?? _defaultSystemPrompt;
      print('SettingsService: Загружен системный промпт (длина: ${value.length})');
      return value;
    } catch (e) {
      print('SettingsService: Ошибка при загрузке системного промпта: $e');
      return _defaultSystemPrompt;
    }
  }

  // Сохранить системный промпт
  static Future<bool> saveSystemPrompt(String systemPrompt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = await prefs.setString(_systemPromptKey, systemPrompt);
      print('SettingsService: Сохранен системный промпт (длина: ${systemPrompt.length}), результат: $result');
      // Дополнительная проверка - читаем обратно
      final verify = prefs.getString(_systemPromptKey);
      print('SettingsService: Проверка сохранения - прочитано (длина: ${verify?.length ?? 0})');
      return result;
    } catch (e, stackTrace) {
      print('SettingsService: Ошибка при сохранении системного промпта: $e');
      print('SettingsService: Stack trace: $stackTrace');
      return false;
    }
  }

  // Загрузить провайдера
  static Future<String> loadProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_providerKey) ?? _defaultProvider;
      print('SettingsService: Загружен провайдер: $value');
      return value;
    } catch (e) {
      print('SettingsService: Ошибка при загрузке провайдера: $e');
      return _defaultProvider;
    }
  }

  // Сохранить провайдера
  static Future<bool> saveProvider(String provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = await prefs.setString(_providerKey, provider);
      print('SettingsService: Сохранен провайдер $provider, результат: $result');
      return result;
    } catch (e, stackTrace) {
      print('SettingsService: Ошибка при сохранении провайдера: $e');
      print('SettingsService: Stack trace: $stackTrace');
      return false;
    }
  }

  // Загрузить модель
  static Future<String> loadModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_modelKey) ?? _defaultModel;
      print('SettingsService: Загружена модель: $value');
      return value;
    } catch (e) {
      print('SettingsService: Ошибка при загрузке модели: $e');
      return _defaultModel;
    }
  }

  // Сохранить модель
  static Future<bool> saveModel(String model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = await prefs.setString(_modelKey, model);
      print('SettingsService: Сохранена модель $model, результат: $result');
      return result;
    } catch (e, stackTrace) {
      print('SettingsService: Ошибка при сохранении модели: $e');
      print('SettingsService: Stack trace: $stackTrace');
      return false;
    }
  }

  // Загрузить порог суммаризации
  static Future<int> loadSummarizationThreshold() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(_summarizationThresholdKey) ?? _defaultSummarizationThreshold;
      print('SettingsService: Загружен порог суммаризации: $value');
      return value;
    } catch (e) {
      print('SettingsService: Ошибка при загрузке порога суммаризации: $e');
      return _defaultSummarizationThreshold;
    }
  }

  // Сохранить порог суммаризации
  static Future<bool> saveSummarizationThreshold(int threshold) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = await prefs.setInt(_summarizationThresholdKey, threshold);
      print('SettingsService: Сохранен порог суммаризации $threshold, результат: $result');
      // Дополнительная проверка - читаем обратно
      final verify = prefs.getInt(_summarizationThresholdKey);
      print('SettingsService: Проверка сохранения - прочитано: $verify');
      return result;
    } catch (e, stackTrace) {
      print('SettingsService: Ошибка при сохранении порога суммаризации: $e');
      print('SettingsService: Stack trace: $stackTrace');
      return false;
    }
  }

  // Загрузить состояние памяти
  static Future<bool> loadUseMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_useMemoryKey) ?? _defaultUseMemory;
      print('SettingsService: Загружено состояние памяти: $value');
      return value;
    } catch (e) {
      print('SettingsService: Ошибка при загрузке состояния памяти: $e');
      return _defaultUseMemory;
    }
  }

  // Сохранить состояние памяти
  static Future<bool> saveUseMemory(bool useMemory) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = await prefs.setBool(_useMemoryKey, useMemory);
      print('SettingsService: Сохранено состояние памяти $useMemory, результат: $result');
      // Дополнительная проверка - читаем обратно
      final verify = prefs.getBool(_useMemoryKey);
      print('SettingsService: Проверка сохранения - прочитано: $verify');
      return result;
    } catch (e, stackTrace) {
      print('SettingsService: Ошибка при сохранении состояния памяти: $e');
      print('SettingsService: Stack trace: $stackTrace');
      return false;
    }
  }

  // Загрузить все настройки
  static Future<Map<String, dynamic>> loadAllSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final temperature = prefs.getDouble(_temperatureKey) ?? _defaultTemperature;
      final systemPrompt = prefs.getString(_systemPromptKey) ?? _defaultSystemPrompt;
      final provider = prefs.getString(_providerKey) ?? _defaultProvider;
      final model = prefs.getString(_modelKey) ?? _defaultModel;
      final summarizationThreshold = prefs.getInt(_summarizationThresholdKey) ?? _defaultSummarizationThreshold;
      final useMemory = prefs.getBool(_useMemoryKey) ?? _defaultUseMemory;
      print('SettingsService: Загружены все настройки - температура: $temperature, промпт длина: ${systemPrompt.length}, провайдер: $provider, модель: $model, порог суммаризации: $summarizationThreshold, память: $useMemory');
      return {
        'temperature': temperature,
        'systemPrompt': systemPrompt,
        'provider': provider,
        'model': model,
        'summarizationThreshold': summarizationThreshold,
        'useMemory': useMemory,
      };
    } catch (e) {
      print('SettingsService: Ошибка при загрузке всех настроек: $e');
      return {
        'temperature': _defaultTemperature,
        'systemPrompt': _defaultSystemPrompt,
        'provider': _defaultProvider,
        'model': _defaultModel,
        'summarizationThreshold': _defaultSummarizationThreshold,
        'useMemory': _defaultUseMemory,
      };
    }
  }
}
