import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/chat_state.dart';
import '../bloc/chat_event.dart';
import '../models/mcp_server.dart';

class McpServersDialog extends StatelessWidget {
  const McpServersDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      builder: (context, state) {
        final servers = state.mcpServers ?? [];
        final isLoading = state.mcpToolsLoading;

        return Dialog(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
              child: Column(
                children: [
                  // Заголовок
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.dns),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Управление MCP серверами',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  // Список серверов
                  Expanded(
                    child: isLoading && servers.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : servers.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.dns_outlined,
                                      size: 64,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Нет настроенных серверов',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: servers.length,
                                itemBuilder: (context, index) {
                                  final server = servers[index];
                                  return _ServerCard(server: server);
                                },
                              ),
                  ),
                  const Divider(),
                  // Кнопки
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            context.read<ChatBloc>().add(const LoadMcpServers());
                          },
                          child: const Text('Обновить'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            _showAddServerDialog(context);
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Добавить сервер'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
  }

  void _showAddServerDialog(BuildContext context) {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final descriptionController = TextEditingController();
    bool enabled = true;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Добавить MCP сервер'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: idController,
                      decoration: const InputDecoration(
                        labelText: 'ID сервера *',
                        hintText: 'unique-server-id',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Название *',
                        hintText: 'My MCP Server',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: 'URL *',
                        hintText: 'http://localhost:5001',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Описание',
                        hintText: 'Опциональное описание',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text('Включен'),
                      value: enabled,
                      onChanged: (value) {
                        setState(() {
                          enabled = value ?? true;
                        });
                      },
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
                    if (idController.text.isEmpty ||
                        nameController.text.isEmpty ||
                        urlController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Заполните все обязательные поля'),
                        ),
                      );
                      return;
                    }

                    context.read<ChatBloc>().add(AddMcpServer(
                          id: idController.text,
                          name: nameController.text,
                          url: urlController.text,
                          enabled: enabled,
                          description: descriptionController.text,
                        ));

                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Добавить'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ServerCard extends StatelessWidget {
  final McpServer server;

  const _ServerCard({required this.server});

  @override
  Widget build(BuildContext context) {
    final status = server.connectionStatus ?? 'disconnected';
    final statusColor = status == 'connected'
        ? Colors.green
        : status == 'error'
            ? Colors.red
            : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.dns,
          color: statusColor,
        ),
        title: Text(server.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(server.url),
            if (server.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                server.description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status == 'connected'
                        ? 'Подключен'
                        : status == 'error'
                            ? 'Ошибка'
                            : 'Отключен',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (server.enabled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Включен',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'test':
                context.read<ChatBloc>().add(TestMcpServer(server.id));
                break;
              case 'connect':
                context.read<ChatBloc>().add(ConnectMcpServer(server.id));
                break;
              case 'disconnect':
                context.read<ChatBloc>().add(DisconnectMcpServer(server.id));
                break;
              case 'edit':
                _showEditServerDialog(context, server);
                break;
              case 'delete':
                _showDeleteConfirmDialog(context, server);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'test',
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 20),
                  SizedBox(width: 8),
                  Text('Тестировать'),
                ],
              ),
            ),
            if (status != 'connected')
              const PopupMenuItem(
                value: 'connect',
                child: Row(
                  children: [
                    Icon(Icons.link, size: 20),
                    SizedBox(width: 8),
                    Text('Подключить'),
                  ],
                ),
              ),
            if (status == 'connected')
              const PopupMenuItem(
                value: 'disconnect',
                child: Row(
                  children: [
                    Icon(Icons.link_off, size: 20),
                    SizedBox(width: 8),
                    Text('Отключить'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Редактировать'),
                ],
              ),
            ),
            if (server.id != 'local-bluetooth')
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Удалить', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showEditServerDialog(BuildContext context, McpServer server) {
    final nameController = TextEditingController(text: server.name);
    final urlController = TextEditingController(text: server.url);
    final descriptionController = TextEditingController(text: server.description);
    bool enabled = server.enabled;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Редактировать MCP сервер'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Название *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: 'URL *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Описание',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text('Включен'),
                      value: enabled,
                      onChanged: (value) {
                        setState(() {
                          enabled = value ?? true;
                        });
                      },
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
                    if (nameController.text.isEmpty || urlController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Заполните все обязательные поля'),
                        ),
                      );
                      return;
                    }

                    context.read<ChatBloc>().add(UpdateMcpServer(
                          serverId: server.id,
                          updates: {
                            'name': nameController.text,
                            'url': urlController.text,
                            'description': descriptionController.text,
                            'enabled': enabled,
                          },
                        ));

                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, McpServer server) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Удалить сервер?'),
          content: Text('Вы уверены, что хотите удалить сервер "${server.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                context.read<ChatBloc>().add(DeleteMcpServer(server.id));
                Navigator.of(dialogContext).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
  }
}
