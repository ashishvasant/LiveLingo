import 'dart:convert';

enum InteractionMode { guide, autonomous }

extension InteractionModeX on InteractionMode {
  String get wireValue => switch (this) {
    InteractionMode.guide => 'guide',
    InteractionMode.autonomous => 'autonomous',
  };

  String get label => switch (this) {
    InteractionMode.guide => 'Guide',
    InteractionMode.autonomous => 'Autonomous',
  };

  static InteractionMode fromWireValue(String? value) {
    return switch ((value ?? '').trim().toLowerCase()) {
      'autonomous' => InteractionMode.autonomous,
      _ => InteractionMode.guide,
    };
  }
}

class AppSettings {
  const AppSettings({
    required this.backendUrl,
    required this.authToken,
    required this.userLanguage,
    required this.targetLanguage,
    required this.liveVoiceName,
    required this.targetLanguageAutoInfer,
    required this.allowLocationFallback,
    required this.includeCameraContext,
    required this.saveLocalHistory,
    required this.playbackSpeed,
    required this.transliterationStyle,
    required this.interactionMode,
    required this.muteReplies,
    required this.audioInputEnabled,
    required this.autonomousShowAllMessages,
    required this.defaultAutonomousGoal,
    required this.profileName,
    required this.profileEmail,
    required this.updatedAt,
  });

  final String backendUrl;
  final String authToken;
  final String userLanguage;
  final String targetLanguage;
  final String liveVoiceName;
  final bool targetLanguageAutoInfer;
  final bool allowLocationFallback;
  final bool includeCameraContext;
  final bool saveLocalHistory;
  final double playbackSpeed;
  final String transliterationStyle;
  final InteractionMode interactionMode;
  final bool muteReplies;
  final bool audioInputEnabled;
  final bool autonomousShowAllMessages;
  final String defaultAutonomousGoal;
  final String profileName;
  final String profileEmail;
  final DateTime updatedAt;

  factory AppSettings.defaults() {
    return AppSettings(
      backendUrl: const String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8080'),
      authToken: '',
      userLanguage: 'English',
      targetLanguage: 'Kannada',
      liveVoiceName: 'Kore',
      targetLanguageAutoInfer: true,
      allowLocationFallback: true,
      includeCameraContext: false,
      saveLocalHistory: true,
      playbackSpeed: 1.0,
      transliterationStyle: 'default',
      interactionMode: InteractionMode.guide,
      muteReplies: false,
      audioInputEnabled: true,
      autonomousShowAllMessages: false,
      defaultAutonomousGoal: '',
      profileName: '',
      profileEmail: '',
      updatedAt: DateTime.now().toUtc(),
    );
  }

  AppSettings copyWith({
    String? backendUrl,
    String? authToken,
    String? userLanguage,
    String? targetLanguage,
    String? liveVoiceName,
    bool? targetLanguageAutoInfer,
    bool? allowLocationFallback,
    bool? includeCameraContext,
    bool? saveLocalHistory,
    double? playbackSpeed,
    String? transliterationStyle,
    InteractionMode? interactionMode,
    bool? muteReplies,
    bool? audioInputEnabled,
    bool? autonomousShowAllMessages,
    String? defaultAutonomousGoal,
    String? profileName,
    String? profileEmail,
    DateTime? updatedAt,
  }) {
    return AppSettings(
      backendUrl: backendUrl ?? this.backendUrl,
      authToken: authToken ?? this.authToken,
      userLanguage: userLanguage ?? this.userLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      liveVoiceName: liveVoiceName ?? this.liveVoiceName,
      targetLanguageAutoInfer:
          targetLanguageAutoInfer ?? this.targetLanguageAutoInfer,
      allowLocationFallback:
          allowLocationFallback ?? this.allowLocationFallback,
      includeCameraContext: includeCameraContext ?? this.includeCameraContext,
      saveLocalHistory: saveLocalHistory ?? this.saveLocalHistory,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      transliterationStyle: transliterationStyle ?? this.transliterationStyle,
      interactionMode: interactionMode ?? this.interactionMode,
      muteReplies: muteReplies ?? this.muteReplies,
      audioInputEnabled: audioInputEnabled ?? this.audioInputEnabled,
      autonomousShowAllMessages:
          autonomousShowAllMessages ?? this.autonomousShowAllMessages,
      defaultAutonomousGoal:
          defaultAutonomousGoal ?? this.defaultAutonomousGoal,
      profileName: profileName ?? this.profileName,
      profileEmail: profileEmail ?? this.profileEmail,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toDbMap() {
    return <String, Object?>{
      'id': 1,
      'backend_url': backendUrl,
      'auth_token': authToken,
      'user_language': userLanguage,
      'target_language': targetLanguage,
      'live_voice_name': liveVoiceName,
      'target_language_auto_infer': targetLanguageAutoInfer ? 1 : 0,
      'allow_location_fallback': allowLocationFallback ? 1 : 0,
      'include_camera_context': includeCameraContext ? 1 : 0,
      'save_local_history': saveLocalHistory ? 1 : 0,
      'playback_speed': playbackSpeed,
      'transliteration_style': transliterationStyle,
      'interaction_mode': interactionMode.wireValue,
      'mute_replies': muteReplies ? 1 : 0,
      'audio_input_enabled': audioInputEnabled ? 1 : 0,
      'autonomous_show_all_messages': autonomousShowAllMessages ? 1 : 0,
      'default_autonomous_goal': defaultAutonomousGoal,
      'profile_name': profileName,
      'profile_email': profileEmail,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory AppSettings.fromDbMap(Map<String, Object?> map) {
    return AppSettings(
      backendUrl: map['backend_url'] as String? ?? '',
      authToken: map['auth_token'] as String? ?? '',
      userLanguage: map['user_language'] as String? ?? 'English',
      targetLanguage: map['target_language'] as String? ?? 'Kannada',
      liveVoiceName: map['live_voice_name'] as String? ?? 'Kore',
      targetLanguageAutoInfer:
          (map['target_language_auto_infer'] as int? ?? 1) == 1,
      allowLocationFallback: (map['allow_location_fallback'] as int? ?? 1) == 1,
      includeCameraContext: (map['include_camera_context'] as int? ?? 0) == 1,
      saveLocalHistory: (map['save_local_history'] as int? ?? 1) == 1,
      playbackSpeed: (map['playback_speed'] as num? ?? 1.0).toDouble(),
      transliterationStyle:
          map['transliteration_style'] as String? ?? 'default',
      interactionMode: InteractionModeX.fromWireValue(
        map['interaction_mode'] as String?,
      ),
      muteReplies: (map['mute_replies'] as int? ?? 0) == 1,
      audioInputEnabled: (map['audio_input_enabled'] as int? ?? 1) == 1,
      autonomousShowAllMessages:
          (map['autonomous_show_all_messages'] as int? ?? 0) == 1,
      defaultAutonomousGoal: map['default_autonomous_goal'] as String? ?? '',
      profileName: map['profile_name'] as String? ?? '',
      profileEmail: map['profile_email'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toSessionConfig({
    required bool cameraEnabled,
    required String autonomousGoal,
    required String contextOverride,
  }) {
    final String currentTask = contextOverride.trim().isNotEmpty
        ? contextOverride.trim()
        : autonomousGoal.trim();
    return <String, Object?>{
      'type': 'session_config',
      'user_language': userLanguage,
      'target_language_mode': targetLanguageAutoInfer ? 'auto' : 'manual',
      'target_language': targetLanguage,
      'voice_name': liveVoiceName,
      'interaction_mode': interactionMode.wireValue,
      'mute_responses': muteReplies,
      'audio_input_enabled': audioInputEnabled,
      'enable_camera_context': cameraEnabled,
      'allow_location_fallback': allowLocationFallback,
      'save_local_history': saveLocalHistory,
      'audio_playback_speed': playbackSpeed,
      'autonomous_goal': autonomousGoal,
      'context_override': contextOverride,
      'current_task': currentTask,
    };
  }
}

class AuthenticatedUser {
  const AuthenticatedUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.idToken,
    this.photoUrl,
  });

  final String uid;
  final String email;
  final String displayName;
  final String idToken;
  final String? photoUrl;
}

class ScenarioState {
  const ScenarioState({
    required this.locationGuess,
    required this.locationSource,
    required this.localLanguage,
    required this.userLanguage,
    required this.scenario,
    required this.subscenario,
    required this.activeSpeakerRole,
    required this.recentEntities,
    required this.confidence,
    required this.updatedAt,
    required this.contextSummary,
    required this.contextSource,
    required this.manualOverrideActive,
  });

  final String locationGuess;
  final String locationSource;
  final String localLanguage;
  final String userLanguage;
  final String scenario;
  final String subscenario;
  final String activeSpeakerRole;
  final List<String> recentEntities;
  final double confidence;
  final DateTime updatedAt;
  final String contextSummary;
  final String contextSource;
  final bool manualOverrideActive;

  factory ScenarioState.fromMap(Map<String, dynamic> map) {
    return ScenarioState(
      locationGuess: map['location_guess'] as String? ?? 'unknown nearby place',
      locationSource: map['location_source'] as String? ?? 'audio_only',
      localLanguage: map['local_language'] as String? ?? 'Unknown',
      userLanguage: map['user_language'] as String? ?? 'English',
      scenario: map['scenario'] as String? ?? 'general assistance',
      subscenario: map['subscenario'] as String? ?? 'listening for context',
      activeSpeakerRole:
          map['active_speaker_role'] as String? ?? 'ambient_only',
      recentEntities: (map['recent_entities'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic value) => value.toString())
          .toList(),
      confidence: (map['confidence'] as num? ?? 0.0).toDouble(),
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      contextSummary:
          map['context_summary'] as String? ?? 'Listening for context',
      contextSource: map['context_source'] as String? ?? 'audio_only',
      manualOverrideActive: map['manual_override_active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'location_guess': locationGuess,
      'location_source': locationSource,
      'local_language': localLanguage,
      'user_language': userLanguage,
      'scenario': scenario,
      'subscenario': subscenario,
      'active_speaker_role': activeSpeakerRole,
      'recent_entities': recentEntities,
      'confidence': confidence,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'context_summary': contextSummary,
      'context_source': contextSource,
      'manual_override_active': manualOverrideActive,
    };
  }
}

class PhraseSuggestion {
  const PhraseSuggestion({
    required this.id,
    required this.displayText,
    required this.targetText,
    required this.transliteration,
    required this.pronunciationHint,
    required this.audioAvailable,
    required this.rank,
    required this.reason,
  });

  final String id;
  final String displayText;
  final String targetText;
  final String transliteration;
  final String pronunciationHint;
  final bool audioAvailable;
  final int rank;
  final String reason;

  factory PhraseSuggestion.fromMap(Map<String, dynamic> map) {
    return PhraseSuggestion(
      id: map['id'] as String? ?? '',
      displayText: map['display_text'] as String? ?? '',
      targetText: map['target_text'] as String? ?? '',
      transliteration: map['transliteration'] as String? ?? '',
      pronunciationHint: map['pronunciation_hint'] as String? ?? '',
      audioAvailable: map['audio_available'] as bool? ?? false,
      rank: (map['rank'] as num? ?? 0).toInt(),
      reason: map['reason'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'display_text': displayText,
      'target_text': targetText,
      'transliteration': transliteration,
      'pronunciation_hint': pronunciationHint,
      'audio_available': audioAvailable,
      'rank': rank,
      'reason': reason,
    };
  }
}

class IntentAssist {
  const IntentAssist({
    required this.confidence,
    required this.inputSummary,
    required this.displayText,
    required this.targetText,
    required this.transliteration,
    required this.pronunciationHint,
    required this.audioAvailable,
  });

  final double confidence;
  final String inputSummary;
  final String displayText;
  final String targetText;
  final String transliteration;
  final String pronunciationHint;
  final bool audioAvailable;

  factory IntentAssist.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic> result =
        (map['result'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return IntentAssist(
      confidence: (map['confidence'] as num? ?? 0.0).toDouble(),
      inputSummary: map['input_summary'] as String? ?? '',
      displayText: result['display_text'] as String? ?? '',
      targetText: result['target_text'] as String? ?? '',
      transliteration: result['transliteration'] as String? ?? '',
      pronunciationHint: result['pronunciation_hint'] as String? ?? '',
      audioAvailable: result['audio_available'] as bool? ?? false,
    );
  }
}

class AssistantReply {
  const AssistantReply({
    required this.targetText,
    required this.translatedText,
    required this.transliteration,
    required this.pronunciationHint,
    required this.audioAvailable,
    required this.spoken,
    this.audioBase64,
    this.mimeType,
  });

  final String targetText;
  final String translatedText;
  final String transliteration;
  final String pronunciationHint;
  final bool audioAvailable;
  final bool spoken;
  final String? audioBase64;
  final String? mimeType;

  factory AssistantReply.fromMap(Map<String, dynamic> map) {
    return AssistantReply(
      targetText: map['target_text'] as String? ?? '',
      translatedText: map['translated_text'] as String? ?? '',
      transliteration: map['transliteration'] as String? ?? '',
      pronunciationHint: map['pronunciation_hint'] as String? ?? '',
      audioAvailable: map['audio_available'] as bool? ?? false,
      spoken: map['spoken'] as bool? ?? false,
      audioBase64: map['audio_base64'] as String?,
      mimeType: map['mime_type'] as String?,
    );
  }
}

class AutonomousStatus {
  const AutonomousStatus({
    required this.goal,
    required this.status,
    required this.summary,
    required this.completionConfidence,
  });

  final String goal;
  final String status;
  final String summary;
  final double completionConfidence;

  factory AutonomousStatus.initial([String goal = '']) {
    return AutonomousStatus(
      goal: goal,
      status: goal.isEmpty ? 'idle' : 'waiting_for_interaction',
      summary: goal.isEmpty ? 'No autonomous goal yet.' : 'Ready to start.',
      completionConfidence: 0,
    );
  }

  factory AutonomousStatus.fromMap(Map<String, dynamic> map) {
    return AutonomousStatus(
      goal: map['goal'] as String? ?? '',
      status: map['status'] as String? ?? 'idle',
      summary: map['summary'] as String? ?? '',
      completionConfidence: (map['completion_confidence'] as num? ?? 0)
          .toDouble(),
    );
  }
}

class TranscriptEvent {
  const TranscriptEvent({
    required this.speaker,
    required this.originalText,
    required this.userLanguageText,
    required this.targetLanguageText,
    required this.isFinal,
    required this.timestamp,
    this.sourceLanguage = '',
    this.needsTranslation = false,
  });

  final String speaker;
  final String originalText;
  final String userLanguageText;
  final String targetLanguageText;
  final bool isFinal;
  final DateTime timestamp;
  final String sourceLanguage;
  final bool needsTranslation;

  factory TranscriptEvent.fromMap(Map<String, dynamic> map) {
    return TranscriptEvent(
      speaker: map['speaker'] as String? ?? 'user',
      originalText: map['original_text'] as String? ?? '',
      userLanguageText: map['user_language_text'] as String? ?? '',
      targetLanguageText: map['target_language_text'] as String? ?? '',
      isFinal: map['is_final'] as bool? ?? true,
      timestamp:
          DateTime.tryParse(map['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      sourceLanguage: map['source_language'] as String? ?? '',
      needsTranslation: map['needs_translation'] as bool? ?? false,
    );
  }
}

class ReplySuggestionCard {
  const ReplySuggestionCard({
    required this.id,
    required this.targetText,
    required this.transliteration,
    required this.meaningEn,
  });

  final String id;
  final String targetText;
  final String transliteration;
  final String meaningEn;

  factory ReplySuggestionCard.fromMap(Map<String, dynamic> map) {
    return ReplySuggestionCard(
      id: map['id'] as String? ?? '',
      targetText: map['target_text'] as String? ?? '',
      transliteration: map['transliteration'] as String? ?? '',
      meaningEn: map['meaning_en'] as String? ?? '',
    );
  }
}

class HeardMessage {
  const HeardMessage({
    required this.messageId,
    required this.speakerLabel,
    required this.translatedText,
    required this.sourceLanguage,
    required this.originalText,
    required this.replySuggestions,
    required this.timestamp,
  });

  final String messageId;
  final String speakerLabel;
  final String translatedText;
  final String sourceLanguage;
  final String originalText;
  final List<ReplySuggestionCard> replySuggestions;
  final DateTime timestamp;

  factory HeardMessage.fromMap(Map<String, dynamic> map) {
    return HeardMessage(
      messageId: map['message_id'] as String? ?? '',
      speakerLabel: map['speaker_label'] as String? ?? 'Other person said',
      translatedText: map['translated_text'] as String? ?? '',
      sourceLanguage: map['source_language'] as String? ?? 'Unknown',
      originalText: map['original_text'] as String? ?? '',
      replySuggestions:
          (map['reply_suggestions'] as List<dynamic>? ?? <dynamic>[])
              .map(
                (dynamic item) =>
                    ReplySuggestionCard.fromMap(item as Map<String, dynamic>),
              )
              .toList(),
      timestamp:
          DateTime.tryParse(map['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}

class QuickReplyResult {
  const QuickReplyResult({
    required this.requestId,
    required this.sourceMessageId,
    required this.targetLanguage,
    required this.userText,
    required this.targetText,
    required this.transliteration,
    required this.meaningEn,
    this.audioBase64,
    this.mimeType,
  });

  final String requestId;
  final String sourceMessageId;
  final String targetLanguage;
  final String userText;
  final String targetText;
  final String transliteration;
  final String meaningEn;
  final String? audioBase64;
  final String? mimeType;

  factory QuickReplyResult.fromMap(Map<String, dynamic> map) {
    return QuickReplyResult(
      requestId: map['request_id'] as String? ?? '',
      sourceMessageId: map['source_message_id'] as String? ?? '',
      targetLanguage: map['target_language'] as String? ?? 'Unknown',
      userText: map['user_text'] as String? ?? '',
      targetText: map['target_text'] as String? ?? '',
      transliteration: map['transliteration'] as String? ?? '',
      meaningEn: map['meaning_en'] as String? ?? '',
      audioBase64: map['audio_base64'] as String?,
      mimeType: map['mime_type'] as String?,
    );
  }
}

class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.role,
    required this.title,
    required this.translatedText,
    required this.originalText,
    required this.language,
    required this.timestamp,
    this.transliteration = '',
  });

  final String id;
  final String role;
  final String title;
  final String translatedText;
  final String originalText;
  final String language;
  final String transliteration;
  final DateTime timestamp;
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

class AutonomousPrompt {
  const AutonomousPrompt({
    required this.promptId,
    required this.question,
    required this.options,
    required this.allowFreeText,
  });

  final String promptId;
  final String question;
  final List<AutonomousPromptOption> options;
  final bool allowFreeText;

  factory AutonomousPrompt.fromMap(Map<String, dynamic> map) {
    return AutonomousPrompt(
      promptId: map['prompt_id'] as String? ?? '',
      question: map['question'] as String? ?? '',
      options: (map['options'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (dynamic item) =>
                AutonomousPromptOption.fromMap(item as Map<String, dynamic>),
          )
          .toList(),
      allowFreeText: map['allow_free_text'] as bool? ?? true,
    );
  }
}

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.createdAt,
    required this.interactionMode,
    required this.goal,
    required this.contextSummary,
    required this.targetLanguage,
    required this.outcome,
  });

  final String id;
  final DateTime createdAt;
  final String interactionMode;
  final String goal;
  final String contextSummary;
  final String targetLanguage;
  final String outcome;

  factory SessionSummary.fromMap(Map<String, Object?> map) {
    return SessionSummary(
      id: map['id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      interactionMode: map['interaction_mode'] as String? ?? 'guide',
      goal: map['goal'] as String? ?? '',
      contextSummary: map['context_summary'] as String? ?? '',
      targetLanguage: map['target_language'] as String? ?? '',
      outcome: map['outcome'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'created_at': createdAt.toUtc().toIso8601String(),
      'interaction_mode': interactionMode,
      'goal': goal,
      'context_summary': contextSummary,
      'target_language': targetLanguage,
      'outcome': outcome,
    };
  }
}

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.createdAt,
    required this.source,
    required this.userLanguage,
    required this.targetLanguage,
    required this.suggestionId,
    required this.displayText,
    required this.targetText,
    required this.transliteration,
    required this.pronunciationHint,
    required this.scenario,
    required this.locationGuess,
    required this.audioPlayed,
  });

  final String id;
  final DateTime createdAt;
  final String source;
  final String userLanguage;
  final String targetLanguage;
  final String suggestionId;
  final String displayText;
  final String targetText;
  final String transliteration;
  final String pronunciationHint;
  final String scenario;
  final String locationGuess;
  final bool audioPlayed;

  factory HistoryEntry.fromMap(Map<String, Object?> map) {
    return HistoryEntry(
      id: map['id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      source: map['source'] as String? ?? 'predicted',
      userLanguage: map['user_language'] as String? ?? 'English',
      targetLanguage: map['target_language'] as String? ?? 'Unknown',
      suggestionId: map['suggestion_id'] as String? ?? '',
      displayText: map['display_text'] as String? ?? '',
      targetText: map['target_text'] as String? ?? '',
      transliteration: map['transliteration'] as String? ?? '',
      pronunciationHint: map['pronunciation_hint'] as String? ?? '',
      scenario: map['scenario'] as String? ?? '',
      locationGuess: map['location_guess'] as String? ?? '',
      audioPlayed: (map['audio_played'] as int? ?? 0) == 1,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'created_at': createdAt.toUtc().toIso8601String(),
      'source': source,
      'user_language': userLanguage,
      'target_language': targetLanguage,
      'suggestion_id': suggestionId,
      'display_text': displayText,
      'target_text': targetText,
      'transliteration': transliteration,
      'pronunciation_hint': pronunciationHint,
      'scenario': scenario,
      'location_guess': locationGuess,
      'audio_played': audioPlayed ? 1 : 0,
    };
  }
}

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.id,
    required this.createdAt,
    required this.type,
    required this.payload,
  });

  final String id;
  final DateTime createdAt;
  final String type;
  final Map<String, dynamic> payload;

  factory DiagnosticEvent.fromMap(Map<String, Object?> map) {
    return DiagnosticEvent(
      id: map['id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      type: map['type'] as String? ?? 'unknown',
      payload:
          jsonDecode(map['payload_json'] as String? ?? '{}')
              as Map<String, dynamic>,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'created_at': createdAt.toUtc().toIso8601String(),
      'type': type,
      'payload_json': jsonEncode(payload),
    };
  }
}

class LiveLanguageState {
  const LiveLanguageState({
    required this.liveConnected,
    required this.micStreaming,
    required this.cameraEnabled,
    required this.userLanguage,
    required this.targetLanguage,
    required this.connectionStatus,
    required this.interactionMode,
    required this.muteReplies,
    required this.audioInputEnabled,
    required this.currentGoal,
    required this.contextOverride,
    required this.suggestions,
    required this.recentHistory,
    required this.heardMessages,
    required this.transcriptEvents,
    required this.autonomousConversation,
    required this.autonomousStatus,
    required this.awaitingGoalCapture,
    required this.awaitingLanguageCapture,
    required this.awaitingUserSpeechCapture,
    required this.autonomousPaused,
    this.currentState,
    this.currentIntentAssist,
    this.lastAssistantReply,
    this.latestQuickReply,
    this.autonomousPrompt,
    this.activeQuickReplyMessageId,
    this.lastScenarioUpdateAt,
  });

  final bool liveConnected;
  final bool micStreaming;
  final bool cameraEnabled;
  final String userLanguage;
  final String? targetLanguage;
  final String connectionStatus;
  final InteractionMode interactionMode;
  final bool muteReplies;
  final bool audioInputEnabled;
  final String currentGoal;
  final String contextOverride;
  final ScenarioState? currentState;
  final List<PhraseSuggestion> suggestions;
  final IntentAssist? currentIntentAssist;
  final AssistantReply? lastAssistantReply;
  final List<HistoryEntry> recentHistory;
  final List<HeardMessage> heardMessages;
  final List<TranscriptEvent> transcriptEvents;
  final List<ConversationMessage> autonomousConversation;
  final AutonomousStatus autonomousStatus;
  final bool awaitingGoalCapture;
  final bool awaitingLanguageCapture;
  final bool awaitingUserSpeechCapture;
  final bool autonomousPaused;
  final QuickReplyResult? latestQuickReply;
  final AutonomousPrompt? autonomousPrompt;
  final String? activeQuickReplyMessageId;
  final DateTime? lastScenarioUpdateAt;

  factory LiveLanguageState.initial(AppSettings settings) {
    return LiveLanguageState(
      liveConnected: false,
      micStreaming: false,
      cameraEnabled: settings.includeCameraContext,
      userLanguage: settings.userLanguage,
      targetLanguage: settings.targetLanguage,
      connectionStatus: 'idle',
      interactionMode: settings.interactionMode,
      muteReplies: settings.muteReplies,
      audioInputEnabled: settings.audioInputEnabled,
      currentGoal: settings.defaultAutonomousGoal,
      contextOverride: '',
      suggestions: const <PhraseSuggestion>[],
      recentHistory: const <HistoryEntry>[],
      heardMessages: const <HeardMessage>[],
      transcriptEvents: const <TranscriptEvent>[],
      autonomousConversation: const <ConversationMessage>[],
      autonomousStatus: AutonomousStatus.initial(
        settings.defaultAutonomousGoal,
      ),
      awaitingGoalCapture: false,
      awaitingLanguageCapture: false,
      awaitingUserSpeechCapture: false,
      autonomousPaused: false,
    );
  }

  LiveLanguageState copyWith({
    bool? liveConnected,
    bool? micStreaming,
    bool? cameraEnabled,
    String? userLanguage,
    String? targetLanguage,
    String? connectionStatus,
    InteractionMode? interactionMode,
    bool? muteReplies,
    bool? audioInputEnabled,
    String? currentGoal,
    String? contextOverride,
    ScenarioState? currentState,
    List<PhraseSuggestion>? suggestions,
    IntentAssist? currentIntentAssist,
    AssistantReply? lastAssistantReply,
    List<HistoryEntry>? recentHistory,
    List<HeardMessage>? heardMessages,
    List<TranscriptEvent>? transcriptEvents,
    List<ConversationMessage>? autonomousConversation,
    AutonomousStatus? autonomousStatus,
    bool? awaitingGoalCapture,
    bool? awaitingLanguageCapture,
    bool? awaitingUserSpeechCapture,
    bool? autonomousPaused,
    QuickReplyResult? latestQuickReply,
    AutonomousPrompt? autonomousPrompt,
    String? activeQuickReplyMessageId,
    DateTime? lastScenarioUpdateAt,
    bool clearIntentAssist = false,
    bool clearAssistantReply = false,
    bool clearQuickReply = false,
    bool clearAutonomousPrompt = false,
    bool clearActiveQuickReplyMessageId = false,
  }) {
    return LiveLanguageState(
      liveConnected: liveConnected ?? this.liveConnected,
      micStreaming: micStreaming ?? this.micStreaming,
      cameraEnabled: cameraEnabled ?? this.cameraEnabled,
      userLanguage: userLanguage ?? this.userLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      interactionMode: interactionMode ?? this.interactionMode,
      muteReplies: muteReplies ?? this.muteReplies,
      audioInputEnabled: audioInputEnabled ?? this.audioInputEnabled,
      currentGoal: currentGoal ?? this.currentGoal,
      contextOverride: contextOverride ?? this.contextOverride,
      currentState: currentState ?? this.currentState,
      suggestions: suggestions ?? this.suggestions,
      currentIntentAssist: clearIntentAssist
          ? null
          : currentIntentAssist ?? this.currentIntentAssist,
      lastAssistantReply: clearAssistantReply
          ? null
          : lastAssistantReply ?? this.lastAssistantReply,
      recentHistory: recentHistory ?? this.recentHistory,
      heardMessages: heardMessages ?? this.heardMessages,
      transcriptEvents: transcriptEvents ?? this.transcriptEvents,
      autonomousConversation:
          autonomousConversation ?? this.autonomousConversation,
      autonomousStatus: autonomousStatus ?? this.autonomousStatus,
      awaitingGoalCapture: awaitingGoalCapture ?? this.awaitingGoalCapture,
      awaitingLanguageCapture:
          awaitingLanguageCapture ?? this.awaitingLanguageCapture,
      awaitingUserSpeechCapture:
          awaitingUserSpeechCapture ?? this.awaitingUserSpeechCapture,
      autonomousPaused: autonomousPaused ?? this.autonomousPaused,
      latestQuickReply: clearQuickReply
          ? null
          : latestQuickReply ?? this.latestQuickReply,
      autonomousPrompt: clearAutonomousPrompt
          ? null
          : autonomousPrompt ?? this.autonomousPrompt,
      activeQuickReplyMessageId: clearActiveQuickReplyMessageId
          ? null
          : activeQuickReplyMessageId ?? this.activeQuickReplyMessageId,
      lastScenarioUpdateAt: lastScenarioUpdateAt ?? this.lastScenarioUpdateAt,
    );
  }
}
