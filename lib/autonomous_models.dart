class AutonomousConversationMessage {
  const AutonomousConversationMessage({
    required this.id,
    required this.role,
    required this.translatedText,
    required this.originalText,
    required this.sourceLanguage,
    required this.timestamp,
  });

  final String id;
  final String role;
  final String translatedText;
  final String originalText;
  final String sourceLanguage;
  final DateTime timestamp;

  factory AutonomousConversationMessage.fromMap(Map<String, dynamic> map) {
    return AutonomousConversationMessage(
      id: map['message_id'] as String? ?? '',
      role: map['role'] as String? ?? 'system',
      translatedText: map['translated_text'] as String? ?? '',
      originalText: map['original_text'] as String? ?? '',
      sourceLanguage: map['source_language'] as String? ?? '',
      timestamp:
          DateTime.tryParse(map['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}

class AutonomousPromptOption {
  const AutonomousPromptOption({required this.label, required this.value});

  final String label;
  final String value;

  factory AutonomousPromptOption.fromMap(Map<String, dynamic> map) {
    return AutonomousPromptOption(
      label: map['label'] as String? ?? '',
      value: map['value'] as String? ?? '',
    );
  }
}

class AutonomousPromptState {
  const AutonomousPromptState({
    required this.toolCallId,
    required this.question,
    required this.options,
    required this.allowFreeText,
    required this.context,
  });

  final String toolCallId;
  final String question;
  final List<AutonomousPromptOption> options;
  final bool allowFreeText;
  final String context;

  AutonomousPromptState copyWith({
    String? toolCallId,
    String? question,
    List<AutonomousPromptOption>? options,
    bool? allowFreeText,
    String? context,
  }) {
    return AutonomousPromptState(
      toolCallId: toolCallId ?? this.toolCallId,
      question: question ?? this.question,
      options: options ?? this.options,
      allowFreeText: allowFreeText ?? this.allowFreeText,
      context: context ?? this.context,
    );
  }

  factory AutonomousPromptState.fromMap(Map<String, dynamic> map) {
    final List<dynamic> rawOptions =
        map['options'] as List<dynamic>? ?? const <dynamic>[];
    return AutonomousPromptState(
      toolCallId: map['tool_call_id'] as String? ?? '',
      question: map['question'] as String? ?? '',
      options: rawOptions
          .whereType<Map<String, dynamic>>()
          .map(AutonomousPromptOption.fromMap)
          .toList(),
      allowFreeText: map['allow_free_text'] as bool? ?? true,
      context: map['context'] as String? ?? '',
    );
  }
}

class AutonomousStatusState {
  const AutonomousStatusState({
    required this.status,
    required this.summary,
    required this.task,
    required this.placeLanguage,
  });

  final String status;
  final String summary;
  final String task;
  final String placeLanguage;

  factory AutonomousStatusState.initial() {
    return const AutonomousStatusState(
      status: 'idle',
      summary: 'Ready to start.',
      task: '',
      placeLanguage: '',
    );
  }

  AutonomousStatusState copyWith({
    String? status,
    String? summary,
    String? task,
    String? placeLanguage,
  }) {
    return AutonomousStatusState(
      status: status ?? this.status,
      summary: summary ?? this.summary,
      task: task ?? this.task,
      placeLanguage: placeLanguage ?? this.placeLanguage,
    );
  }

  factory AutonomousStatusState.fromMap(Map<String, dynamic> map) {
    return AutonomousStatusState(
      status: map['status'] as String? ?? 'idle',
      summary: map['summary'] as String? ?? '',
      task: map['task'] as String? ?? '',
      placeLanguage: map['place_language'] as String? ?? '',
    );
  }
}
