import 'package:equatable/equatable.dart';
import '../models/message.dart';

abstract class ChatState extends Equatable {
  final double temperature;
  final String systemPrompt;
  final String provider;
  final String model;
  final Map<String, dynamic>? availableModels;
  final int summarizationThreshold;
  final bool useMemory;

  const ChatState({
    this.temperature = 0.7,
    this.systemPrompt = '',
    this.provider = 'deepseek',
    this.model = '',
    this.availableModels,
    this.summarizationThreshold = 1000,
    this.useMemory = false,
  });

  @override
  List<Object?> get props => [temperature, systemPrompt, provider, model, availableModels, summarizationThreshold, useMemory];
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
  });

  @override
  List<Object?> get props => [messages, currentTopic, temperature, systemPrompt, provider, model, availableModels, summarizationThreshold, useMemory];
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
  });

  @override
  List<Object?> get props => [messages, currentTopic, ltmUsed, ltmEmpty, ltmMessagesCount, ltmQuery, temperature, systemPrompt, provider, model, availableModels, summarizationThreshold, useMemory];
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
  });

  @override
  List<Object?> get props => [messages, error, temperature, systemPrompt, provider, model, availableModels, summarizationThreshold, useMemory];
}
