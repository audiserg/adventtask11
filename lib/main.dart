import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/chat_bloc.dart';
import 'bloc/chat_state.dart';
import 'bloc/chat_event.dart';
import 'models/message.dart';
import 'widgets/chat_message.dart';
import 'widgets/chat_input.dart';
import 'widgets/mcp_tools_panel.dart';
import 'widgets/mcp_servers_dialog.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Лучший диалог с LLM',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: BlocProvider(
        create: (context) => ChatBloc(),
        child: const ChatScreen(),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  void initState() {
    super.initState();
    // Загружаем MCP инструменты и серверы при инициализации
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatBloc>().add(const LoadMcpTools());
      context.read<ChatBloc>().add(const LoadMcpServers());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<ChatBloc, ChatState>(
          builder: (context, state) {
            String title = 'Лучший диалог с LLM';
            if (state is ChatLoaded && state.currentTopic != null) {
              title = state.currentTopic!;
            } else if (state is ChatLoading && state.currentTopic != null) {
              title = state.currentTopic!;
            }
            return Text(title);
          },
        ),
        centerTitle: true,
        actions: [
          // Иконка выбора провайдера и модели
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              return IconButton(
                icon: const Icon(Icons.model_training),
                tooltip: 'Выбор провайдера и модели',
                onPressed: () => _showModelSelectorDialog(context, state),
              );
            },
          ),
          // Иконка настройки температуры
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              return IconButton(
                icon: const Icon(Icons.thermostat),
                tooltip: 'Настройка температуры',
                onPressed: () => _showTemperatureDialog(context, state.temperature),
              );
            },
          ),
          // Иконка настройки системного промпта
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              return IconButton(
                icon: const Icon(Icons.settings_applications),
                tooltip: 'Настройка системного промпта',
                onPressed: () => _showSystemPromptDialog(context, state.systemPrompt),
              );
            },
          ),
          // Иконка настройки порога суммаризации
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              return IconButton(
                icon: const Icon(Icons.compress),
                tooltip: 'Настройка порога суммаризации',
                onPressed: () => _showSummarizationThresholdDialog(context, state.summarizationThreshold),
              );
            },
          ),
          // Checkbox для включения памяти
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              return Tooltip(
                message: state.useMemory ? 'Память включена' : 'Включить память',
                child: Checkbox(
                  value: state.useMemory,
                  onChanged: (value) {
                    if (value != null) {
                      context.read<ChatBloc>().add(ToggleMemory(value));
                    }
                  },
                ),
              );
            },
          ),
          // Кнопка очистки памяти (показывается только если память включена)
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              if (!state.useMemory) {
                return const SizedBox.shrink();
              }

              return IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'Очистить память',
                onPressed: () {
                  _showClearMemoryDialog(context);
                },
              );
            },
          ),
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              final hasMessages = state is ChatLoaded ||
                  state is ChatLoading ||
                  (state is ChatError && state.messages.isNotEmpty);

              if (!hasMessages) {
                return const SizedBox.shrink();
              }

              return IconButton(
                icon: const Icon(Icons.clear_all),
                tooltip: 'Очистить чат',
                onPressed: () {
                  context.read<ChatBloc>().add(const ClearChat());
                },
              );
            },
          ),
          // MCP инструменты
          IconButton(
            icon: const Icon(Icons.build),
            tooltip: 'MCP инструменты',
            onPressed: () {
              _showMcpToolsDialog(context);
            },
          ),
          // Управление MCP серверами
          IconButton(
            icon: const Icon(Icons.dns),
            tooltip: 'Управление MCP серверами',
            onPressed: () {
              _showMcpServersDialog(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                if (state is ChatInitial) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Начните разговор с ИИ',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                        ),
                      ],
                    ),
                  );
                }

                List<Message> messages = [];
                if (state is ChatLoading) {
                  messages = state.messages;
                } else if (state is ChatLoaded) {
                  messages = state.messages;
                } else if (state is ChatError) {
                  messages = state.messages;
                }

                if (messages.isEmpty) {
                  return const Center(child: Text('Нет сообщений'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length + (state is ChatLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < messages.length) {
                      return ChatMessageWidget(
                        message: messages[index],
                        messageIndex: index,
                      );
                    } else {
                      // Показываем индикатор загрузки
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ),
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              if (state is ChatError) {
                return Container(
                  padding: const EdgeInsets.all(8),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const ChatInputWidget(),
        ],
      ),
    );
  }

  static void _showTemperatureDialog(BuildContext context, double currentTemperature) {
    final controller = TextEditingController(text: currentTemperature.toString());
    // Получаем ChatBloc из правильного контекста до создания диалога
    final chatBloc = context.read<ChatBloc>();
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Настройка температуры'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Температура (0.0 - 2.0)',
                  hintText: '0.7',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              const Text(
                'Температура контролирует случайность ответов:\n'
                '• 0.0 - более детерминированные ответы\n'
                '• 0.7 - баланс (рекомендуется)\n'
                '• 2.0 - более креативные ответы',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () async {
                final value = double.tryParse(controller.text);
                if (value != null && value >= 0.0 && value <= 2.0) {
                  chatBloc.add(UpdateTemperature(value));
                  Navigator.of(dialogContext).pop();
                  // Показываем подтверждение - используем оригинальный контекст
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Температура сохранена: ${value.toStringAsFixed(1)}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Введите значение от 0.0 до 2.0'),
                    ),
                  );
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  static void _showSystemPromptDialog(BuildContext context, String currentSystemPrompt) {
    final controller = TextEditingController(text: currentSystemPrompt);
    // Получаем ChatBloc из правильного контекста до создания диалога
    final chatBloc = context.read<ChatBloc>();
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Настройка системного промпта'),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Системный промпт',
                hintText: 'Оставьте пустым для использования по умолчанию',
                alignLabelWithHint: true,
              ),
              maxLines: 10,
              minLines: 5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                chatBloc.add(UpdateSystemPrompt(controller.text));
                Navigator.of(dialogContext).pop();
                // Показываем подтверждение - используем оригинальный контекст
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(controller.text.isEmpty 
                        ? 'Системный промпт сброшен (будет использован по умолчанию)'
                        : 'Системный промпт сохранен'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  static void _showSummarizationThresholdDialog(BuildContext context, int currentThreshold) {
    final controller = TextEditingController(text: currentThreshold.toString());
    // Получаем ChatBloc из правильного контекста до создания диалога
    final chatBloc = context.read<ChatBloc>();
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Настройка порога суммаризации'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Порог токенов (100 - 100000)',
                  hintText: '1000',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Text(
                'Порог суммаризации определяет, когда автоматически суммаризировать контекст:\n'
                '• При превышении порога старые сообщения заменяются на суммаризацию\n'
                '• Рекомендуется: 1000-5000 токенов\n'
                '• Меньше значение = чаще суммаризация',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () async {
                final value = int.tryParse(controller.text);
                if (value != null && value >= 100 && value <= 100000) {
                  chatBloc.add(UpdateSummarizationThreshold(value));
                  Navigator.of(dialogContext).pop();
                  // Показываем подтверждение - используем оригинальный контекст
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Порог суммаризации сохранен: $value токенов'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Введите значение от 100 до 100000'),
                    ),
                  );
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  static void _showModelSelectorDialog(BuildContext context, ChatState state) {
    final chatBloc = context.read<ChatBloc>();
    
    // Загружаем список моделей, если еще не загружен
    if (state.availableModels == null) {
      chatBloc.add(const LoadModels());
    }
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return BlocProvider.value(
          value: chatBloc,
          child: BlocBuilder<ChatBloc, ChatState>(
            builder: (context, currentState) {
              final bloc = context.read<ChatBloc>();
              return StatefulBuilder(
                builder: (context, setDialogState) {
                  return AlertDialog(
                  title: const Text('Выбор провайдера и модели'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Выбор провайдера
                          const Text(
                            'Провайдер:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('DeepSeek'),
                                  value: 'deepseek',
                                  groupValue: currentState.provider,
                                    onChanged: (value) {
                                      if (value != null) {
                                        bloc.add(UpdateProvider(value));
                                      }
                                    },
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('Hugging Face'),
                                  value: 'huggingface',
                                  groupValue: currentState.provider,
                                    onChanged: (value) {
                                      if (value != null) {
                                        bloc.add(UpdateProvider(value));
                                      }
                                    },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Выбор модели
                          const Text(
                            'Модель:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          // Предустановленные модели
                            if (currentState.availableModels != null)
                              _buildPresetModels(
                                context,
                                currentState,
                                bloc,
                              ),
                            const SizedBox(height: 8),
                            // Полный список моделей
                            if (currentState.availableModels != null)
                              _buildModelList(
                                context,
                                currentState,
                                bloc,
                              )
                          else
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Закрыть'),
                    ),
                  ],
                );
                },
              );
            },
          ),
        );
      },
    );
  }

  static Widget _buildPresetModels(
    BuildContext context,
    ChatState state,
    ChatBloc bloc,
  ) {
    final providers = state.availableModels?['providers'] as Map<String, dynamic>?;
    if (providers == null) return const SizedBox.shrink();
    
    final providerKey = state.provider;
    final providerData = providers[providerKey] as Map<String, dynamic>?;
    if (providerData == null) return const SizedBox.shrink();
    
    final presets = providerData['presets'] as Map<String, dynamic>?;
    if (presets == null) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Предустановленные:',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _buildPresetChip(
              context,
              'Топовая',
              presets['top'] as String? ?? '',
              state.model,
              bloc,
            ),
            _buildPresetChip(
              context,
              'Средняя',
              presets['medium'] as String? ?? '',
              state.model,
              bloc,
            ),
            _buildPresetChip(
              context,
              'Легкая',
              presets['light'] as String? ?? '',
              state.model,
              bloc,
            ),
          ],
        ),
      ],
    );
  }

  static Widget _buildPresetChip(
    BuildContext context,
    String label,
    String model,
    String currentModel,
    ChatBloc bloc,
  ) {
    final isSelected = currentModel == model;
    // Извлекаем короткое название модели (последняя часть после /)
    final modelName = model.split('/').last;
    return Tooltip(
      message: model, // Полное название модели в tooltip
      child: FilterChip(
        label: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 2),
            Text(
              modelName,
              style: TextStyle(
                fontSize: 10,
                color: isSelected 
                  ? Theme.of(context).colorScheme.onSecondaryContainer
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) {
            bloc.add(UpdateModel(model));
          }
        },
      ),
    );
  }

  static Widget _buildModelList(
    BuildContext context,
    ChatState state,
    ChatBloc bloc,
  ) {
    final providers = state.availableModels?['providers'] as Map<String, dynamic>?;
    if (providers == null) return const SizedBox.shrink();
    
    final providerKey = state.provider;
    final providerData = providers[providerKey] as Map<String, dynamic>?;
    if (providerData == null) return const SizedBox.shrink();
    
    final models = providerData['models'] as List<dynamic>?;
    if (models == null || models.isEmpty) {
      return const Text('Нет доступных моделей');
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Все модели:',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 200,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: models.length,
            itemBuilder: (context, index) {
              final modelName = models[index].toString();
              final isSelected = state.model == modelName;
              return RadioListTile<String>(
                title: Text(
                  modelName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                value: modelName,
                groupValue: state.model.isEmpty ? null : state.model,
                onChanged: (value) {
                  if (value != null) {
                    bloc.add(UpdateModel(value));
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  static void _showClearMemoryDialog(BuildContext context) {
    final chatBloc = context.read<ChatBloc>();
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Очистить память'),
          content: const Text(
            'Вы уверены, что хотите очистить всю историю сообщений из памяти? '
            'Это действие нельзя отменить.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  chatBloc.add(const ClearMemory());
                  // Показываем подтверждение после небольшой задержки
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Память очищена'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ошибка при очистке памяти: $e'),
                        duration: const Duration(seconds: 3),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Очистить'),
            ),
          ],
        );
      },
    );
  }

  static void _showMcpToolsDialog(BuildContext context) {
    final chatBloc = context.read<ChatBloc>();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return BlocProvider.value(
          value: chatBloc,
          child: Dialog(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.build),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'MCP Инструменты',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Обновить',
                          onPressed: () {
                            chatBloc.add(const LoadMcpTools());
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  const Expanded(
                    child: McpToolsPanel(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static void _showMcpServersDialog(BuildContext context) {
    final chatBloc = context.read<ChatBloc>();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return BlocProvider.value(
          value: chatBloc,
          child: const McpServersDialog(),
        );
      },
    );
  }
}
