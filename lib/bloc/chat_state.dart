import 'package:equatable/equatable.dart';
import '../models/message.dart';
import '../models/mcp_tool.dart';
import '../models/mcp_server.dart';

abstract class ChatState extends Equatable {
  final double temperature;
  final String systemPrompt;
  final String provider;
  final String model;
  final Map<String, dynamic>? availableModels;
  final int summarizationThreshold;
  final bool useMemory;
  final List<McpTool>? mcpTools;
  final List<McpServer>? mcpServers;
  final bool mcpToolsLoading;
  final String? mcpError;

  const ChatState({
    this.temperature = 0.7,
    this.systemPrompt = '',
    this.provider = 'deepseek',
    this.model = '',
    this.availableModels,
    this.summarizationThreshold = 1000,
    this.useMemory = false,
    this.mcpTools,
    this.mcpServers,
    this.mcpToolsLoading = false,
    this.mcpError,
  });

  @override
  List<Object?> get props => [
    temperature,
    systemPrompt,
    provider,
    model,
    availableModels,
    summarizationThreshold,
    useMemory,
    mcpTools,
    mcpServers,
    mcpToolsLoading,
    mcpError,
  ];
}

class ChatInitial extends ChatState {
  const ChatInitial({
    super.temperature,
    super.systemPrompt,
    super.provider,
    super.model,
    super.availableModels,
    super.summarizationThreshold,
    super.useMemory,
    super.mcpTools,
    super.mcpServers,
    super.mcpToolsLoading,
    super.mcpError,
  });
}

class ChatLoading extends ChatState {
  final List<Message> messages;
  final String? currentTopic;

  const ChatLoading(
    this.messages, {
    this.currentTopic,
    super.temperature,
    super.systemPrompt,
    super.provider,
    super.model,
    super.availableModels,
    super.summarizationThreshold,
    super.useMemory,
    super.mcpTools,
    super.mcpServers,
    super.mcpToolsLoading,
    super.mcpError,
  });

  @override
  List<Object?> get props => [
    messages,
    currentTopic,
    temperature,
    systemPrompt,
    provider,
    model,
    availableModels,
    summarizationThreshold,
    useMemory,
    mcpTools,
    mcpServers,
    mcpToolsLoading,
    mcpError,
  ];
}

class ChatLoaded extends ChatState {
  final List<Message> messages;
  final String? currentTopic;
  final bool? ltmUsed;
  final bool? ltmEmpty;
  final int? ltmMessagesCount;
  final String? ltmQuery;

  const ChatLoaded(
    this.messages, {
    this.currentTopic,
    this.ltmUsed,
    this.ltmEmpty,
    this.ltmMessagesCount,
    this.ltmQuery,
    super.temperature,
    super.systemPrompt,
    super.provider,
    super.model,
    super.availableModels,
    super.summarizationThreshold,
    super.useMemory,
    super.mcpTools,
    super.mcpServers,
    super.mcpToolsLoading,
    super.mcpError,
  });

  @override
  List<Object?> get props => [
    messages,
    currentTopic,
    ltmUsed,
    ltmEmpty,
    ltmMessagesCount,
    ltmQuery,
    temperature,
    systemPrompt,
    provider,
    model,
    availableModels,
    summarizationThreshold,
    useMemory,
    mcpTools,
    mcpServers,
    mcpToolsLoading,
    mcpError,
  ];
}

class ChatError extends ChatState {
  final List<Message> messages;
  final String error;

  const ChatError(
    this.messages,
    this.error, {
    super.temperature,
    super.systemPrompt,
    super.provider,
    super.model,
    super.availableModels,
    super.summarizationThreshold,
    super.useMemory,
    super.mcpTools,
    super.mcpServers,
    super.mcpToolsLoading,
    super.mcpError,
  });

  @override
  List<Object?> get props => [
    messages,
    error,
    temperature,
    systemPrompt,
    provider,
    model,
    availableModels,
    summarizationThreshold,
    useMemory,
    mcpTools,
    mcpServers,
    mcpToolsLoading,
    mcpError,
  ];
}
