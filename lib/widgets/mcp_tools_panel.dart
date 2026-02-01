import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/chat_state.dart';
import '../bloc/chat_event.dart';
import '../models/mcp_tool.dart';

class McpToolsPanel extends StatelessWidget {
  const McpToolsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      builder: (context, state) {
        final tools = state.mcpTools ?? [];
        final isLoading = state.mcpToolsLoading;
        final error = state.mcpError;

        if (isLoading && tools.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (error != null && tools.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ошибка загрузки инструментов',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    error,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      context.read<ChatBloc>().add(const LoadMcpTools());
                    },
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          );
        }

        if (tools.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.build_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Нет доступных инструментов',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Подключите MCP сервер для получения инструментов',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        // Группируем инструменты по серверам
        final toolsByServer = <String, List<McpTool>>{};
        for (final tool in tools) {
          final serverKey = tool.serverName ?? tool.serverId ?? 'Unknown';
          toolsByServer.putIfAbsent(serverKey, () => []).add(tool);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: toolsByServer.length,
          itemBuilder: (context, index) {
            final serverName = toolsByServer.keys.elementAt(index);
            final serverTools = toolsByServer[serverName]!;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                leading: const Icon(Icons.dns),
                title: Text(serverName),
                subtitle: Text('${serverTools.length} инструмент(ов)'),
                children: serverTools.map((tool) {
                  return ListTile(
                    leading: const Icon(Icons.build),
                    title: Text(tool.name),
                    subtitle: Text(
                      tool.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_arrow),
                      tooltip: 'Выполнить инструмент',
                      onPressed: () {
                        _showToolDialog(context, tool);
                      },
                    ),
                  );
                }).toList(),
              ),
            );
          },
        );
      },
    );
  }

  void _showToolDialog(BuildContext context, McpTool tool) {
    final argsController = <String, TextEditingController>{};
    final rawProps = tool.inputSchema['properties'];
    final inputSchema = rawProps is Map
        ? Map<String, dynamic>.from(rawProps)
        : <String, dynamic>{};

    // Создаем контроллеры для каждого параметра
    for (final entry in inputSchema.entries) {
      argsController[entry.key] = TextEditingController();
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Выполнить: ${tool.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tool.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (argsController.isNotEmpty) ...[
                  Text(
                    'Параметры:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ...argsController.entries.map((entry) {
                    final paramName = entry.key;
                    final controller = entry.value;
                    final paramSchema = inputSchema[paramName] as Map<String, dynamic>? ?? {};
                    final paramType = paramSchema['type'] as String? ?? 'string';
                    final paramDescription = paramSchema['description'] as String? ?? '';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: paramName,
                          hintText: paramDescription,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: paramType == 'number'
                            ? const TextInputType.numberWithOptions(decimal: true)
                            : TextInputType.text,
                      ),
                    );
                  }),
                ] else
                  Text(
                    'Инструмент не требует параметров',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                final args = <String, dynamic>{};
                for (final entry in argsController.entries) {
                  final value = entry.value.text;
                  if (value.isNotEmpty) {
                    final paramSchema = inputSchema[entry.key] as Map<String, dynamic>? ?? {};
                    final paramType = paramSchema['type'] as String? ?? 'string';
                    
                    if (paramType == 'number') {
                      final numValue = num.tryParse(value);
                      if (numValue != null) {
                        args[entry.key] = numValue;
                      }
                    } else if (paramType == 'boolean') {
                      args[entry.key] = value.toLowerCase() == 'true';
                    } else {
                      args[entry.key] = value;
                    }
                  }
                }

                context.read<ChatBloc>().add(CallMcpTool(
                      toolName: tool.name,
                      serverId: tool.serverId ?? '',
                      args: args,
                    ));

                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Инструмент ${tool.name} выполняется...'),
                  ),
                );
              },
              child: const Text('Выполнить'),
            ),
          ],
        );
      },
    );
  }
}
