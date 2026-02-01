import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Один сервер в формате Cursor: либо url (SSE), либо command + args (stdio).
class McpServerEntry {
  String name;
  String? url;
  String? command;
  List<String> args;
  Map<String, String>? env;

  McpServerEntry({
    required this.name,
    this.url,
    this.command,
    List<String>? args,
    this.env,
  }) : args = args ?? [];

  bool get isUrl => url != null && url!.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    if (isUrl) {
      return {'url': url!.trim()};
    }
    final m = <String, dynamic>{
      'command': (command ?? '').trim(),
      'args': args.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
    };
    if (env != null && env!.isNotEmpty) {
      m['env'] = Map<String, String>.from(env!);
    }
    return m;
  }

  static McpServerEntry fromJson(String name, Map<String, dynamic> json) {
    final url = json['url'] as String?;
    final command = json['command'] as String?;
    final argsRaw = json['args'];
    List<String> args = [];
    if (argsRaw is List) {
      for (final e in argsRaw) {
        if (e != null) args.add(e.toString());
      }
    }
    final envRaw = json['env'];
    Map<String, String>? env;
    if (envRaw is Map) {
      env = {};
      for (final e in envRaw.entries) {
        if (e.value != null) env[e.key.toString()] = e.value.toString();
      }
    }
    return McpServerEntry(
      name: name,
      url: url?.trim().isNotEmpty == true ? url : null,
      command: command?.trim().isNotEmpty == true ? command : null,
      args: args,
      env: env?.isEmpty == true ? null : env,
    );
  }
}

/// Редактор mcp.json в формате Cursor (mcpServers: url или command + args).
class McpJsonEditor extends StatefulWidget {
  /// После успешной подгрузки серверов в приложение (sync) вызывается этот callback,
  /// например для обновления списка MCP серверов и инструментов.
  final VoidCallback? onSyncDone;

  const McpJsonEditor({super.key, this.onSyncDone});

  @override
  State<McpJsonEditor> createState() => _McpJsonEditorState();
}

class _McpJsonEditorState extends State<McpJsonEditor> {
  final ApiService _api = ApiService();
  final TextEditingController _rawController = TextEditingController();
  List<McpServerEntry> _servers = [];
  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _syncing = false;
  int _tabIndex = 0; // 0 = форма, 1 = JSON

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rawController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _api.getCursorMcpConfig();
      if (mounted) {
        _rawController.text = raw;
        _parseToServers(raw);
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _parseToServers(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>?;
      final serversMap = map?['mcpServers'];
      if (serversMap is! Map) {
        _servers = [];
        return;
      }
      _servers = [];
      for (final e in serversMap.entries) {
        final name = e.key.toString();
        final config = e.value;
        if (config is Map<String, dynamic>) {
          _servers.add(McpServerEntry.fromJson(name, config));
        }
      }
    } catch (_) {
      _servers = [];
    }
  }

  void _formatJson() {
    try {
      final parsed = jsonDecode(_rawController.text) as Map<String, dynamic>;
      _rawController.text = const JsonEncoder.withIndent('  ').convert(parsed);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = 'Неверный JSON: $e');
    }
  }

  String _buildJsonFromForm() {
    final m = <String, dynamic>{};
    for (final s in _servers) {
      if (s.name.trim().isEmpty) continue;
      m[s.name.trim()] = s.toJson();
    }
    return const JsonEncoder.withIndent('  ').convert({'mcpServers': m});
  }

  void _syncFormToRaw() {
    _rawController.text = _buildJsonFromForm();
    setState(() {});
  }

  Future<void> _save() async {
    String raw;
    if (_tabIndex == 0) {
      raw = _buildJsonFromForm();
    } else {
      raw = _rawController.text.trim();
      try {
        jsonDecode(raw) as Map<String, dynamic>;
      } catch (e) {
        setState(() => _error = 'Неверный JSON: $e');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.saveCursorMcpConfig(raw);
      if (mounted) {
        setState(() => _saving = false);
        _rawController.text = raw;
        _parseToServers(raw);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('mcp.json сохранён'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _addServer() {
    setState(() {
      _servers.add(McpServerEntry(name: ''));
    });
  }

  void _removeServer(int index) {
    setState(() {
      _servers.removeAt(index);
    });
  }

  Future<void> _syncToApp() async {
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final result = await _api.syncMcpServersFromCursorConfig();
      if (!mounted) return;
      final added = (result['added'] as List?)?.length ?? 0;
      final message =
          result['message'] as String? ??
          (added > 0 ? 'Добавлено серверов: $added' : 'Готово');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
      widget.onSyncDone?.call();
      setState(() => _syncing = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.code),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Редактор mcp.json',
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
            const Divider(height: 1),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Убедитесь, что бэкенд запущен (npm run dev в папке backend). '
                      'При запуске в браузере или на эмуляторе проверьте доступность http://localhost:3000',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Повторить'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('По форме'),
                    icon: Icon(Icons.list_alt),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('JSON'),
                    icon: Icon(Icons.code),
                  ),
                ],
                selected: {_tabIndex},
                onSelectionChanged: (Set<int> sel) {
                  if (sel.isNotEmpty) {
                    if (sel.first == 0) _syncFormToRaw();
                    setState(() => _tabIndex = sel.first);
                  }
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _tabIndex == 0
                  ? _buildFormTab()
                  : _buildJsonTab(),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Загрузить'),
                  ),
                  if (_tabIndex == 1)
                    TextButton.icon(
                      onPressed: _loading ? null : _formatJson,
                      icon: const Icon(Icons.format_align_left, size: 20),
                      label: const Text('Форматировать'),
                    ),
                  OutlinedButton.icon(
                    onPressed: (_loading || _syncing) ? null : _syncToApp,
                    icon: _syncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download, size: 20),
                    label: Text(
                      _syncing ? 'Подгрузка…' : 'Подгрузить в приложение',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: (_loading || _saving) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save, size: 20),
                    label: Text(_saving ? 'Сохранение…' : 'Сохранить'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text(
                'Серверы (url или command + args)',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addServer,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Добавить'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _servers.length,
            itemBuilder: (context, index) {
              return _ServerFormCard(
                entry: _servers[index],
                onChanged: () => setState(() {}),
                onRemove: () => _removeServer(index),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildJsonTab() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _rawController,
        maxLines: null,
        expands: true,
        decoration: const InputDecoration(
          hintText:
              '{\n  "mcpServers": {\n    "name": { "command": "...", "args": [] }\n  }\n}',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
          contentPadding: EdgeInsets.all(12),
        ),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }
}

class _ServerFormCard extends StatefulWidget {
  final McpServerEntry entry;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _ServerFormCard({
    required this.entry,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_ServerFormCard> createState() => _ServerFormCardState();
}

class _ServerFormCardState extends State<_ServerFormCard> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late TextEditingController _commandController;
  late TextEditingController _argsController;
  bool _useUrl = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.entry.name);
    _urlController = TextEditingController(text: widget.entry.url ?? '');
    _commandController = TextEditingController(
      text: widget.entry.command ?? '',
    );
    _argsController = TextEditingController(
      text: widget.entry.args.isEmpty ? '' : widget.entry.args.join('\n'),
    );
    _useUrl = widget.entry.isUrl;
  }

  @override
  void didUpdateWidget(_ServerFormCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry) {
      _nameController.text = widget.entry.name;
      _urlController.text = widget.entry.url ?? '';
      _commandController.text = widget.entry.command ?? '';
      _argsController.text = widget.entry.args.isEmpty
          ? ''
          : widget.entry.args.join('\n');
      _useUrl = widget.entry.isUrl;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    super.dispose();
  }

  void _apply() {
    widget.entry.name = _nameController.text.trim();
    if (_useUrl) {
      widget.entry.url = _urlController.text.trim().isEmpty
          ? null
          : _urlController.text.trim();
      widget.entry.command = null;
      widget.entry.args = [];
    } else {
      widget.entry.url = null;
      widget.entry.command = _commandController.text.trim().isEmpty
          ? null
          : _commandController.text.trim();
      widget.entry.args = _argsController.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Имя сервера',
                      hintText: 'dart',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _apply(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onRemove,
                  tooltip: 'Удалить',
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('URL (SSE)'),
                  icon: Icon(Icons.link, size: 18),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Command (stdio)'),
                  icon: Icon(Icons.terminal, size: 18),
                ),
              ],
              selected: {_useUrl},
              onSelectionChanged: (Set<bool> sel) {
                if (sel.isNotEmpty) {
                  setState(() {
                    _useUrl = sel.first;
                    _apply();
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            if (_useUrl)
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'http://localhost:64342/sse',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (_) => _apply(),
              )
            else ...[
              TextField(
                controller: _commandController,
                decoration: const InputDecoration(
                  labelText: 'Command',
                  hintText: 'npx / dart / node',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                autocorrect: false,
                onChanged: (_) => _apply(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _argsController,
                decoration: const InputDecoration(
                  labelText: 'Args (каждый аргумент с новой строки)',
                  hintText: '-y\n@mobilenext/mobile-mcp@latest',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  isDense: true,
                ),
                maxLines: 4,
                autocorrect: false,
                onChanged: (_) => _apply(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
