import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../models/mcp_tool.dart';
import '../models/mcp_server.dart';

class ApiService {
  // В production замените на URL вашего сервера
  static const String baseUrl = 'http://localhost:3000';

  Future<Map<String, dynamic>> sendMessage(
    List<Message> messages, {
    double? temperature,
    String? systemPrompt,
    String? provider,
    String? model,
    bool? useMemory,
  }) async {
    try {
      // Преобразуем сообщения в формат для API
      final messagesJson = messages
          .map(
            (msg) => {
              'role': msg.isUser ? 'user' : 'assistant',
              'content': msg.text,
              if (msg.isSummarization) 'isSummarization': true,
            },
          )
          .toList();

      final requestBody = <String, dynamic>{
        'messages': messagesJson,
      };
      
      if (temperature != null) {
        requestBody['temperature'] = temperature;
      }
      
      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        requestBody['systemPrompt'] = systemPrompt;
      }
      
      if (provider != null && provider.isNotEmpty) {
        requestBody['provider'] = provider;
      }
      
      if (model != null && model.isNotEmpty) {
        requestBody['model'] = model;
      }
      
      if (useMemory != null) {
        requestBody['useMemory'] = useMemory;
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(
            const Duration(seconds: 180),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Извлекаем ответ от ИИ
        if (data.containsKey('choices') &&
            (data['choices'] as List).isNotEmpty) {
          final choice = (data['choices'] as List).first;
          if (choice is Map<String, dynamic> && choice.containsKey('message')) {
            final message = choice['message'] as Map<String, dynamic>;
            final content = message['content'] as String? ?? 'No response';
            
            // Извлекаем информацию о токенах
            Map<String, dynamic>? tokenUsage;
            if (data.containsKey('tokenUsage') && data['tokenUsage'] is Map) {
              tokenUsage = data['tokenUsage'] as Map<String, dynamic>;
            }
            
            // Извлекаем информацию о LTM
            final ltmUsed = data['ltmUsed'] as bool?;
            final ltmEmpty = data['ltmEmpty'] as bool?;
            final ltmMessagesCount = data['ltmMessagesCount'] as int?;
            final ltmQuery = data['ltmQuery'] as String?;
            
            // Отладочный вывод
            print('=== API SERVICE LTM DEBUG ===');
            print('ltmUsed from API: ${data['ltmUsed']} (type: ${data['ltmUsed'].runtimeType})');
            print('ltmUsed parsed: $ltmUsed (type: ${ltmUsed.runtimeType})');
            print('ltmEmpty: $ltmEmpty');
            print('ltmMessagesCount: $ltmMessagesCount');
            print('ltmQuery: $ltmQuery');
            print('============================');
            
            return {
              'content': content,
              'tokenUsage': tokenUsage,
              'ltmUsed': ltmUsed,
              'ltmEmpty': ltmEmpty,
              'ltmMessagesCount': ltmMessagesCount,
              'ltmQuery': ltmQuery,
            };
          }
        }

        throw Exception('Invalid response format');
      } else if (response.statusCode == 429) {
        // Ошибка лимита запросов
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          final message =
              errorData['message'] as String? ??
              'Превышен дневной лимит сообщений. Максимум 10 сообщений в день.';
          throw Exception(message);
        } catch (e) {
          if (e is Exception && e.toString().contains('Превышен')) {
            rethrow;
          }
          throw Exception(
            'Превышен дневной лимит сообщений. Максимум 10 сообщений в день.',
          );
        }
      } else {
        String errorMessage = 'Failed to get response: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String? ??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Получить список доступных моделей
  Future<Map<String, dynamic>> getAvailableModels() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/models'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        String errorMessage = 'Failed to get models: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String? ??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Очистка памяти
  Future<bool> clearMemory() async {
    try {
      print('ApiService: Sending DELETE request to /api/memory/clear');
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/memory/clear'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      print('ApiService: Response status: ${response.statusCode}');
      print('ApiService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final success = data['success'] as bool? ?? false;
        final deletedCount = data['deletedCount'] as int? ?? 0;
        print('ApiService: Clear memory result - success: $success, deleted: $deletedCount');
        return success;
      } else {
        String errorMessage = 'Failed to clear memory: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String? ??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        print('ApiService: Error clearing memory: $errorMessage');
        throw Exception(errorMessage);
      }
    } catch (e) {
      print('ApiService: Exception in clearMemory: $e');
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Получение всех сообщений из памяти
  Future<List<Map<String, dynamic>>> getAllMemoryMessages() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/memory/messages?limit=10000'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['messages'] != null) {
          return List<Map<String, dynamic>>.from(data['messages'] as List);
        }
        return [];
      } else {
        String errorMessage = 'Failed to get memory messages: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String? ??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Сохранение сообщения в память
  Future<bool> saveMessageToMemory(String role, String content, {bool isSummarization = false}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/memory/save'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'role': role,
              'content': content,
              'isSummarization': isSummarization,
            }),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['success'] as bool? ?? false;
      } else {
        String errorMessage = 'Failed to save message to memory: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String? ??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Получение количества сообщений в памяти
  Future<int> getMemoryCount() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/memory/count'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['count'] as int? ?? 0;
      } else {
        String errorMessage = 'Failed to get memory count: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String? ??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // MCP API методы
  // Получение списка инструментов
  Future<List<McpTool>> getMcpTools({String? serverId}) async {
    try {
      String url = '$baseUrl/api/mcp/tools';
      if (serverId != null) {
        url += '?serverId=$serverId';
      }

      final response = await http
          .get(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['tools'] != null) {
          final toolsList = data['tools'] as List;
          return toolsList
              .map((tool) => McpTool.fromJson(tool as Map<String, dynamic>))
              .toList();
        }
        return [];
      } else {
        String errorMessage = 'Failed to get MCP tools: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Вызов инструмента
  Future<Map<String, dynamic>> callMcpTool(
    String toolName,
    String serverId,
    Map<String, dynamic> args,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mcp/tools/$toolName'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'serverId': serverId,
              ...args,
            }),
          )
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        String errorMessage = 'Failed to call MCP tool: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Получение статуса MCP
  Future<Map<String, dynamic>> getMcpStatus({String? serverId}) async {
    try {
      String url = '$baseUrl/api/mcp/status';
      if (serverId != null) {
        url += '?serverId=$serverId';
      }

      final response = await http
          .get(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        String errorMessage = 'Failed to get MCP status: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Управление MCP серверами
  // Получение списка серверов
  Future<List<McpServer>> getMcpServers() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/mcp/servers'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['servers'] != null) {
          final serversList = data['servers'] as List;
          return serversList
              .map((server) => McpServer.fromJson(server as Map<String, dynamic>))
              .toList();
        }
        return [];
      } else {
        String errorMessage = 'Failed to get MCP servers: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Добавление сервера
  Future<McpServer> addMcpServer({
    required String id,
    required String name,
    required String url,
    bool enabled = true,
    String description = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mcp/servers'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': id,
              'name': name,
              'url': url,
              'enabled': enabled,
              'description': description,
            }),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['server'] != null) {
          return McpServer.fromJson(data['server'] as Map<String, dynamic>);
        }
        throw Exception('Invalid response format');
      } else {
        String errorMessage = 'Failed to add MCP server: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Обновление сервера
  Future<McpServer> updateMcpServer(
    String serverId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/mcp/servers/$serverId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(updates),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['server'] != null) {
          return McpServer.fromJson(data['server'] as Map<String, dynamic>);
        }
        throw Exception('Invalid response format');
      } else {
        String errorMessage = 'Failed to update MCP server: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Удаление сервера
  Future<bool> deleteMcpServer(String serverId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/mcp/servers/$serverId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['success'] as bool? ?? false;
      } else {
        String errorMessage = 'Failed to delete MCP server: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Тестирование подключения
  Future<Map<String, dynamic>> testMcpServer(String serverId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mcp/servers/$serverId/test'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        String errorMessage = 'Failed to test MCP server: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Подключение к серверу
  Future<Map<String, dynamic>> connectMcpServer(String serverId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mcp/servers/$serverId/connect'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        String errorMessage = 'Failed to connect to MCP server: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  // Отключение от сервера
  Future<Map<String, dynamic>> disconnectMcpServer(String serverId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/mcp/servers/$serverId/disconnect'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        String errorMessage = 'Failed to disconnect from MCP server: ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage =
              errorData['message'] as String? ??
              errorData['error'] as String??
              errorMessage;
        } catch (_) {
          errorMessage = '${response.statusCode}: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }
}
