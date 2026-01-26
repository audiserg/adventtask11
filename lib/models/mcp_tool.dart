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
    return McpTool(
      name: json['name'] as String,
      description: json['description'] as String,
      inputSchema: json['inputSchema'] as Map<String, dynamic>,
      serverId: json['serverId'] as String?,
      serverName: json['serverName'] as String?,
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
