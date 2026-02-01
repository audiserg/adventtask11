class McpServer {
  final String id;
  final String name;
  final String url;
  final bool enabled;
  final String description;
  final String? connectionStatus;
  final DateTime? connectedAt;
  final String? error;
  final String? command;
  final List<String>? args;

  McpServer({
    required this.id,
    required this.name,
    required this.url,
    required this.enabled,
    this.description = '',
    this.connectionStatus,
    this.connectedAt,
    this.error,
    this.command,
    this.args,
  });

  bool get isStdio => command != null && command!.isNotEmpty;

  factory McpServer.fromJson(Map<String, dynamic> json) {
    return McpServer(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String? ?? '',
      enabled: json['enabled'] as bool,
      description: json['description'] as String? ?? '',
      connectionStatus: json['connectionStatus'] as String?,
      connectedAt: json['connectedAt'] != null
          ? DateTime.parse(json['connectedAt'] as String)
          : null,
      error: json['error'] as String?,
      command: (json['command'] as String?)?.isNotEmpty == true ? json['command'] as String? : null,
      args: json['args'] is List ? List<String>.from(json['args'] as List) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'enabled': enabled,
      'description': description,
      if (connectionStatus != null) 'connectionStatus': connectionStatus,
      if (connectedAt != null) 'connectedAt': connectedAt!.toIso8601String(),
      if (error != null) 'error': error,
    };
  }

  McpServer copyWith({
    String? id,
    String? name,
    String? url,
    bool? enabled,
    String? description,
    String? connectionStatus,
    DateTime? connectedAt,
    String? error,
    String? command,
    List<String>? args,
  }) {
    return McpServer(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      enabled: enabled ?? this.enabled,
      description: description ?? this.description,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      connectedAt: connectedAt ?? this.connectedAt,
      error: error ?? this.error,
      command: command ?? this.command,
      args: args ?? this.args,
    );
  }

  @override
  String toString() => 'McpServer(id: $id, name: $name, url: $url, enabled: $enabled)';
}
