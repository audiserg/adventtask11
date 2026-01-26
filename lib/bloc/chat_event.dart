import 'package:equatable/equatable.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class SendMessage extends ChatEvent {
  final String message;

  const SendMessage(this.message);

  @override
  List<Object?> get props => [message];
}

class ClearChat extends ChatEvent {
  const ClearChat();
}

class UpdateTemperature extends ChatEvent {
  final double temperature;

  const UpdateTemperature(this.temperature);

  @override
  List<Object?> get props => [temperature];
}

class UpdateSystemPrompt extends ChatEvent {
  final String systemPrompt;

  const UpdateSystemPrompt(this.systemPrompt);

  @override
  List<Object?> get props => [systemPrompt];
}

class LoadSettings extends ChatEvent {
  const LoadSettings();
}

class UpdateProvider extends ChatEvent {
  final String provider;

  const UpdateProvider(this.provider);

  @override
  List<Object?> get props => [provider];
}

class UpdateModel extends ChatEvent {
  final String model;

  const UpdateModel(this.model);

  @override
  List<Object?> get props => [model];
}

class LoadModels extends ChatEvent {
  const LoadModels();
}

class DeleteMessage extends ChatEvent {
  final int messageIndex;

  const DeleteMessage(this.messageIndex);

  @override
  List<Object?> get props => [messageIndex];
}

class UpdateSummarizationThreshold extends ChatEvent {
  final int threshold;

  const UpdateSummarizationThreshold(this.threshold);

  @override
  List<Object?> get props => [threshold];
}

class ToggleMemory extends ChatEvent {
  final bool enabled;

  const ToggleMemory(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

class ClearMemory extends ChatEvent {
  const ClearMemory();
}
