class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final String? serverId;
  final String? serverName;

  McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    this.serverId,
    this.serverName,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'];
    final rawDesc = json['description'];
    final rawSchema = json['inputSchema'];
    Map<String, dynamic> schema = const {};
    if (rawSchema is Map) {
      try {
        schema = Map<String, dynamic>.from(rawSchema);
      } catch (_) {}
    }
    return McpTool(
      name: rawName is String ? rawName : (rawName?.toString() ?? ''),
      description: rawDesc is String ? rawDesc : (rawDesc?.toString() ?? ''),
      inputSchema: schema,
      serverId: json['serverId'] is String ? json['serverId'] as String? : null,
      serverName: json['serverName'] is String ? json['serverName'] as String? : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'inputSchema': inputSchema,
      if (serverId != null) 'serverId': serverId,
      if (serverName != null) 'serverName': serverName,
    };
  }

  @override
  String toString() => 'McpTool(name: $name, serverId: $serverId)';
}
