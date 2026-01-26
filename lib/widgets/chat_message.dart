import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/message.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';

class ChatMessageWidget extends StatelessWidget {
  final Message message;
  final int? messageIndex;

  const ChatMessageWidget({
    super.key,
    required this.message,
    this.messageIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isAiMessage = !message.isUser;
    final hasEmotion = message.emotion != null;
    
    // Отладочный вывод
    if (isAiMessage) {
      print('=== WIDGET DEBUG ===');
      print('isAiMessage: $isAiMessage');
      print('hasEmotion: $hasEmotion');
      print('emotion value: ${message.emotion}');
      print('emotion type: ${message.emotion.runtimeType}');
      print('message.topic: ${message.topic}');
      print('message.body: ${message.body?.substring(0, message.body!.length > 50 ? 50 : message.body!.length)}...');
      print('message.ltmUsed: ${message.ltmUsed} (type: ${message.ltmUsed.runtimeType})');
      print('message.ltmMessagesCount: ${message.ltmMessagesCount}');
      print('message.ltmQuery: ${message.ltmQuery}');
      print('Will show LTM indicator: ${isAiMessage && message.ltmUsed == true}');
      print('===================');
    }
    
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Цветная полоска и смайлик для AI сообщений
            // Показываем всегда для AI сообщений, даже если emotion null (для отладки)
            if (isAiMessage) ...[
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: hasEmotion 
                      ? _getEmotionColor(message.emotion!)
                      : Colors.grey, // Серый цвет для отладки, если emotion null
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  hasEmotion 
                      ? _getEmotionEmoji(message.emotion!)
                      : '❓', // Вопросительный знак для отладки
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Основной контейнер с сообщением
            Flexible(
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: message.isUser
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MarkdownBody(
                        data: message.isUser 
                            ? message.text 
                            : (message.body ?? 'Ответ получен, но не удалось распарсить формат'),
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: message.isSummarization ? 12 : 16,
                          ),
                          h1: TextStyle(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: message.isSummarization ? 18 : 24,
                            fontWeight: FontWeight.bold,
                          ),
                          h2: TextStyle(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: message.isSummarization ? 15 : 20,
                            fontWeight: FontWeight.bold,
                          ),
                          h3: TextStyle(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: message.isSummarization ? 13 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                          listBullet: TextStyle(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: message.isSummarization ? 12 : 16,
                          ),
                          code: TextStyle(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: message.isSummarization ? 10 : 14,
                            fontFamily: 'monospace',
                            backgroundColor: message.isUser
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                                : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                                : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          blockquote: TextStyle(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.8)
                                : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
                            fontSize: message.isSummarization ? 12 : 16,
                            fontStyle: FontStyle.italic,
                          ),
                          strong: TextStyle(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: message.isSummarization ? 12 : 16,
                            fontWeight: FontWeight.bold,
                          ),
                          em: TextStyle(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: message.isSummarization ? 12 : 16,
                            fontStyle: FontStyle.italic,
                          ),
                          a: TextStyle(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.primary,
                            fontSize: message.isSummarization ? 12 : 16,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatTime(message.timestamp),
                                style: TextStyle(
                                  color: message.isUser
                                      ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                                      : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                  fontSize: 11,
                                ),
                              ),
                              // Температура для AI сообщений
                              if (isAiMessage && message.temperature != null) ...[
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.thermostat,
                                      size: 12,
                                      color: message.isUser
                                          ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                                          : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      message.temperature!.toStringAsFixed(1),
                                      style: TextStyle(
                                        color: message.isUser
                                            ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                                            : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              // Индикатор использования долговременной памяти (LTM)
                              // Проверяем явно на true, чтобы избежать проблем с null
                              if (isAiMessage && (message.ltmUsed == true || message.ltmMessagesCount != null && message.ltmMessagesCount! > 0)) ...[
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: message.ltmMessagesCount != null && message.ltmMessagesCount! > 0
                                      ? 'Использована долговременная память\nЗагружено сообщений: ${message.ltmMessagesCount}\n${message.ltmQuery != null ? 'Запрос: "${message.ltmQuery}"' : ''}'
                                      : 'Использована долговременная память',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.memory,
                                        size: 14,
                                        color: Colors.blue,
                                      ),
                                      if (message.ltmMessagesCount != null && message.ltmMessagesCount! > 0) ...[
                                        const SizedBox(width: 2),
                                        Text(
                                          '${message.ltmMessagesCount}',
                                          style: TextStyle(
                                            color: Colors.blue,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              // Информация о токенах для AI сообщений
                              if (isAiMessage && message.totalTokens != null) ...[
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.numbers,
                                      size: 12,
                                      color: message.isUser
                                          ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                                          : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                    ),
                                    const SizedBox(width: 2),
                                    Tooltip(
                                      message: message.tokensEstimated == true
                                          ? 'Примерный расчет токенов\nВходные: ${message.promptTokens ?? 0}\nВыходные: ${message.completionTokens ?? 0}\nВсего: ${message.totalTokens}${message.maxContextTokens != null ? '\nЛимит: ${message.maxContextTokens}' : ''}${message.contextUsagePercent != null ? '\nИспользовано: ${message.contextUsagePercent!.toStringAsFixed(1)}%' : ''}'
                                          : 'Токены из API\nВходные: ${message.promptTokens ?? 0}\nВыходные: ${message.completionTokens ?? 0}\nВсего: ${message.totalTokens}${message.maxContextTokens != null ? '\nЛимит: ${message.maxContextTokens}' : ''}${message.contextUsagePercent != null ? '\nИспользовано: ${message.contextUsagePercent!.toStringAsFixed(1)}%' : ''}',
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${message.totalTokens}',
                                            style: TextStyle(
                                              color: message.isUser
                                                  ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                                                  : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                              fontSize: 11,
                                            ),
                                          ),
                                          if (message.tokensEstimated == true) ...[
                                            const SizedBox(width: 2),
                                            Icon(
                                              Icons.info_outline,
                                              size: 10,
                                              color: message.isUser
                                                  ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.5)
                                                  : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                // Процент использования контекстного окна
                                if (isAiMessage && message.contextUsagePercent != null && message.maxContextTokens != null) ...[
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: 'Контекстное окно: ${message.totalTokens ?? 0} / ${message.maxContextTokens} токенов (${message.contextUsagePercent!.toStringAsFixed(1)}%)',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.storage,
                                          size: 12,
                                          color: _getContextUsageColor(context, message.contextUsagePercent!),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${message.contextUsagePercent!.toStringAsFixed(1)}%',
                                          style: TextStyle(
                                            color: _getContextUsageColor(context, message.contextUsagePercent!),
                                            fontSize: 11,
                                            fontWeight: message.contextUsagePercent! > 80 ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                          // Кнопки для сообщений пользователя (копировать и удалить)
                          if (message.isUser && messageIndex != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.copy,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _copyMessage(context),
                                  tooltip: 'Копировать',
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _deleteMessage(context),
                                  tooltip: 'Удалить',
                                ),
                              ],
                            )
                          // Иконка info для AI сообщений
                          else if (isAiMessage)
                            InkWell(
                              onTap: () => _showOriginalResponse(context),
                              child: Icon(
                                Icons.info_outline,
                                size: 16,
                                color: message.isUser
                                    ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
                                    : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ),
    );
  }

  Color _getEmotionColor(Emotion emotion) {
    switch (emotion) {
      case Emotion.green:
        return Colors.green;
      case Emotion.blue:
        return Colors.blue;
      case Emotion.red:
        return Colors.red;
    }
  }

  Color _getContextUsageColor(BuildContext context, double percent) {
    if (percent >= 90) {
      return Colors.red;
    } else if (percent >= 70) {
      return Colors.orange;
    } else if (percent >= 50) {
      return Colors.amber;
    } else {
      return message.isUser
          ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)
          : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7);
    }
  }

  String _getEmotionEmoji(Emotion emotion) {
    switch (emotion) {
      case Emotion.green:
        return '😊';
      case Emotion.blue:
        return '😐';
      case Emotion.red:
        return '😔';
    }
  }

  String _formatTime(DateTime timestamp) {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _showOriginalResponse(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Исходный ответ от модели'),
          content: SingleChildScrollView(
            child: SelectableText(
              message.text,
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  void _copyMessage(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Сообщение скопировано в буфер обмена'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _deleteMessage(BuildContext context) {
    if (messageIndex == null) return;
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Удалить сообщение?'),
          content: const Text('Вы уверены, что хотите удалить это сообщение?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                context.read<ChatBloc>().add(DeleteMessage(messageIndex!));
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Сообщение удалено'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
  }
}
