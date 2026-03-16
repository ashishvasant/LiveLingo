import 'dart:async';

import 'package:flutter/material.dart';

import 'autonomous_controller.dart';
import 'autonomous_models.dart';
import 'models.dart' show DiagnosticEvent;

const List<String> _geminiVoiceOptions = <String>[
  'Kore',
  'Puck',
  'Aoede',
  'Charon',
  'Fenrir',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AutonomousController controller =
      await AutonomousController.bootstrap();
  runApp(AutonomousApp(controller: controller));
}

class AutonomousApp extends StatelessWidget {
  const AutonomousApp({super.key, required this.controller});

  final AutonomousController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          title: 'Autonomous Language Assist',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0D6F57),
            ),
            useMaterial3: true,
          ),
          home: !controller.initialized
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : controller.isAuthenticated
              ? AutonomousHomePage(controller: controller)
              : SignInPage(controller: controller),
        );
      },
    );
  }
}

class SignInPage extends StatelessWidget {
  const SignInPage({super.key, required this.controller});

  final AutonomousController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF163B34),
              Color(0xFF27584B),
              Color(0xFFCA7A42),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Autonomous Language Assist',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sign in to start the autonomous live assistant.',
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            controller.authConfigured && !controller.authBusy
                            ? controller.signInWithGoogle
                            : null,
                        icon: controller.authBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(
                          controller.authBusy
                              ? 'Signing in...'
                              : 'Continue with Google',
                        ),
                      ),
                    ),
                    if (controller.authError != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(controller.authError!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AutonomousHomePage extends StatefulWidget {
  const AutonomousHomePage({super.key, required this.controller});

  final AutonomousController controller;

  @override
  State<AutonomousHomePage> createState() => _AutonomousHomePageState();
}

class _AutonomousHomePageState extends State<AutonomousHomePage> {
  late final TextEditingController _taskController;
  late final TextEditingController _placeLanguageController;
  late final TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _taskController = TextEditingController(
      text: widget.controller.currentTask,
    );
    _placeLanguageController = TextEditingController(
      text: widget.controller.currentPlaceLanguage,
    );
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _taskController.dispose();
    _placeLanguageController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    try {
      await widget.controller.startSession(
        task: _taskController.text,
        placeLanguage: _placeLanguageController.text,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _sendResponse({
    String? selectedOption,
    String? selectedOptionLabel,
    String? text,
  }) async {
    final String responseText = text ?? _messageController.text;
    await widget.controller.submitUserResponse(
      responseText,
      selectedOption: selectedOption,
      selectedOptionLabel: selectedOptionLabel,
    );
    _messageController.clear();
  }

  Future<void> _sendVideoContextFrame() async {
    final AutonomousController controller = widget.controller;
    if (!controller.settings.includeCameraContext) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable video context in Settings first.'),
        ),
      );
      return;
    }
    final bool sent = await controller.sendVideoContextFrame();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'Video context frame sent to live session.'
              : 'Could not send video frame right now.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AutonomousController controller = widget.controller;
    final AutonomousPromptState? prompt = controller.activePrompt;
    final bool keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final bool showAllConversation =
        controller.settings.autonomousShowAllMessages;
    final List<AutonomousConversationMessage> visibleMessages =
        showAllConversation
        ? controller.messages
        : controller.messages.where((AutonomousConversationMessage message) {
            return switch (message.role) {
              'assistant_translation' ||
              'assistant' ||
              'other' ||
              'user' ||
              'prompt' => true,
              _ => false,
            };
          }).toList();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Autonomous Assistant'),
            Text(
              controller.connectionStatus,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(controller: controller),
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: controller.authBusy ? null : controller.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (controller.liveConnected)
              _RecordingBanner(
                recording: controller.micStreaming && !controller.paused,
                stopping: controller.sessionStopping,
                onStop: controller.sessionStopping
                    ? null
                    : controller.stopSession,
              ),
            Offstage(
              offstage: keyboardVisible,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: <Widget>[
                        TextField(
                          controller: _taskController,
                          decoration: const InputDecoration(
                            labelText: 'Task',
                            hintText: 'What should the AI get done for you?',
                          ),
                          minLines: 1,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _placeLanguageController,
                          decoration: const InputDecoration(
                            labelText: 'Language of the place',
                            hintText: 'For example: Malayalam, Kannada, French',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: FilledButton(
                                onPressed: controller.sessionStarting
                                    ? null
                                    : _startSession,
                                child: Text(
                                  controller.sessionStarting
                                      ? 'Starting...'
                                      : controller.connectionStatus ==
                                            'Disconnected'
                                      ? 'Reconnect Session'
                                      : controller.liveConnected
                                      ? 'Restart Session'
                                      : 'Start Session',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.tonal(
                                onPressed: !controller.liveConnected
                                    ? null
                                    : controller.paused
                                    ? controller.resumeSession
                                    : controller.pauseSession,
                                child: Text(
                                  controller.paused ? 'Resume' : 'Pause',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            controller.status.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (controller.disconnectMessage != null) ...<Widget>[
                          const SizedBox(height: 12),
                          _DisconnectBanner(
                            message: controller.disconnectMessage!,
                            onRestart: controller.sessionStarting
                                ? null
                                : _startSession,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                color: const Color(0xFFF3EEE8),
                child: controller.messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Start a session to see the live negotiation translated here.',
                        ),
                      )
                    : visibleMessages.isEmpty
                    ? const Center(
                        child: Text('Waiting for translated messages...'),
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: visibleMessages.length,
                        itemBuilder: (BuildContext context, int index) {
                          final AutonomousConversationMessage message =
                              visibleMessages[index];
                          return _ChatBubble(
                            message: message,
                            onReplay:
                                controller.canReplayMessageAudio(message.id)
                                ? () =>
                                      controller.replayMessageAudio(message.id)
                                : null,
                          );
                        },
                      ),
              ),
            ),
            if (prompt != null)
              _PromptComposer(
                prompt: prompt,
                onSelectOption: (AutonomousPromptOption option) {
                  _sendResponse(
                    selectedOption: option.value,
                    selectedOptionLabel: option.label,
                    text: option.label,
                  );
                },
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, keyboardVisible ? 8 : 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: true,
                      decoration: InputDecoration(
                        hintText: prompt != null
                            ? 'Type your answer for the AI'
                            : 'Type a message for the AI',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send video context',
                    onPressed: controller.liveConnected
                        ? _sendVideoContextFrame
                        : null,
                    icon: const Icon(Icons.videocam),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: controller.liveConnected
                        ? () => _sendResponse()
                        : null,
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptComposer extends StatelessWidget {
  const _PromptComposer({required this.prompt, required this.onSelectOption});

  final AutonomousPromptState prompt;
  final ValueChanged<AutonomousPromptOption> onSelectOption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF6EC),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            prompt.question,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (prompt.context.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(prompt.context, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (prompt.options.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: prompt.options
                  .map<Widget>(
                    (AutonomousPromptOption option) => FilledButton.tonal(
                      onPressed: () => onSelectOption(option),
                      child: Text(option.label),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordingBanner extends StatelessWidget {
  const _RecordingBanner({
    required this.recording,
    required this.stopping,
    required this.onStop,
  });

  final bool recording;
  final bool stopping;
  final Future<void> Function()? onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: recording ? const Color(0xFFFFE5E5) : const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: recording ? const Color(0xFFD43A3A) : const Color(0xFF9A9A9A),
          width: 1.2,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            recording ? Icons.fiber_manual_record : Icons.mic_off,
            color: recording
                ? const Color(0xFFD43A3A)
                : const Color(0xFF666666),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              recording ? 'LIVE RECORDING ON' : 'Recording is OFF',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC72A2A),
              foregroundColor: Colors.white,
            ),
            onPressed: onStop == null
                ? null
                : () {
                    unawaited(onStop!());
                  },
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(stopping ? 'Stopping...' : 'Stop'),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, this.onReplay});

  final AutonomousConversationMessage message;
  final Future<void> Function()? onReplay;

  @override
  Widget build(BuildContext context) {
    final _BubbleStyle bubbleStyle = switch (message.role) {
      'assistant_translation' => const _BubbleStyle(
        alignment: CrossAxisAlignment.end,
        color: Color(0xFFD7F5E7),
        title: 'AI speech translated',
      ),
      'assistant_raw' => const _BubbleStyle(
        alignment: CrossAxisAlignment.end,
        color: Color(0xFFEAF8F2),
        title: 'AI speech (original)',
      ),
      'assistant_output_text' => const _BubbleStyle(
        alignment: CrossAxisAlignment.end,
        color: Color(0xFFEEF3FF),
        title: 'AI text output',
      ),
      'assistant' => const _BubbleStyle(
        alignment: CrossAxisAlignment.end,
        color: Color(0xFFD7F5E7),
        title: 'AI speaking for you',
      ),
      'other' => const _BubbleStyle(
        alignment: CrossAxisAlignment.start,
        color: Colors.white,
        title: 'Other person',
      ),
      'user' => const _BubbleStyle(
        alignment: CrossAxisAlignment.end,
        color: Color(0xFFE9EEF9),
        title: 'You',
      ),
      'prompt' => const _BubbleStyle(
        alignment: CrossAxisAlignment.center,
        color: Color(0xFFFFF3D8),
        title: 'AI needs your input',
      ),
      'tool_call' => const _BubbleStyle(
        alignment: CrossAxisAlignment.center,
        color: Color(0xFFFFF2CC),
        title: 'AI tool call',
      ),
      'system_event' => const _BubbleStyle(
        alignment: CrossAxisAlignment.center,
        color: Color(0xFFEFE8DE),
        title: 'System event',
      ),
      _ => const _BubbleStyle(
        alignment: CrossAxisAlignment.center,
        color: Color(0xFFE7E2DB),
        title: 'System',
      ),
    };
    return Column(
      crossAxisAlignment: bubbleStyle.alignment,
      children: <Widget>[
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bubbleStyle.color,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      bubbleStyle.title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onReplay != null)
                    IconButton(
                      tooltip: 'Repeat AI audio',
                      onPressed: () {
                        unawaited(onReplay!());
                      },
                      icon: const Icon(Icons.volume_up),
                    ),
                ],
              ),
              if (message.sourceLanguage.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  message.sourceLanguage,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
              const SizedBox(height: 8),
              Text(message.translatedText),
              if (message.originalText.isNotEmpty &&
                  message.originalText != message.translatedText) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  message.originalText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF505050),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DisconnectBanner extends StatelessWidget {
  const _DisconnectBanner({required this.message, required this.onRestart});

  final String message;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECE5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD97B59)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Connection lost',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(message),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.refresh),
            label: const Text('Restart session'),
          ),
        ],
      ),
    );
  }
}

class _BubbleStyle {
  const _BubbleStyle({
    required this.alignment,
    required this.color,
    required this.title,
  });

  final CrossAxisAlignment alignment;
  final Color color;
  final String title;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AutonomousController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _backendUrlController;
  late final TextEditingController _userLanguageController;
  late String _selectedVoiceName;
  late bool _autonomousShowAllMessages;
  late bool _includeCameraContext;

  @override
  void initState() {
    super.initState();
    _backendUrlController = TextEditingController(
      text: widget.controller.settings.backendUrl,
    );
    _userLanguageController = TextEditingController(
      text: widget.controller.settings.userLanguage,
    );
    _selectedVoiceName = widget.controller.settings.liveVoiceName;
    _autonomousShowAllMessages =
        widget.controller.settings.autonomousShowAllMessages;
    _includeCameraContext = widget.controller.settings.includeCameraContext;
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    _userLanguageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.controller.saveSettings(
      widget.controller.settings.copyWith(
        backendUrl: _backendUrlController.text.trim(),
        userLanguage: _userLanguageController.text.trim(),
        liveVoiceName: _selectedVoiceName,
        autonomousShowAllMessages: _autonomousShowAllMessages,
        includeCameraContext: _includeCameraContext,
      ),
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AutonomousController controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _backendUrlController,
            decoration: const InputDecoration(labelText: 'Backend URL'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userLanguageController,
            decoration: const InputDecoration(labelText: 'Your language'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedVoiceName,
            decoration: const InputDecoration(labelText: 'Gemini voice'),
            items: _geminiVoiceOptions
                .map(
                  (String value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  ),
                )
                .toList(),
            onChanged: (String? value) {
              if (value == null) {
                return;
              }
              setState(() {
                _selectedVoiceName = value;
              });
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show all live messages'),
            subtitle: const Text(
              'Off: translated chat only. On: include raw AI output and tool calls.',
            ),
            value: _autonomousShowAllMessages,
            onChanged: (bool value) {
              setState(() {
                _autonomousShowAllMessages = value;
              });
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable video context'),
            subtitle: const Text(
              'Send periodic camera frames to improve live understanding.',
            ),
            value: _includeCameraContext,
            onChanged: (bool value) {
              setState(() {
                _includeCameraContext = value;
              });
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: controller.clearDiagnostics,
                  child: const Text('Clear logs'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: controller.refreshBackendDebugEvents,
            child: const Text('Refresh Backend Debug'),
          ),
          const SizedBox(height: 20),
          Text(
            'Pipeline status',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Connection: ${controller.connectionStatus}'),
                  Text('Mic streaming: ${controller.micStreaming}'),
                  Text('Native mic chunks: ${controller.nativeMicChunkCount}'),
                  Text(
                    'Uploaded audio frames: ${controller.uploadedAudioFrameCount}',
                  ),
                  Text(
                    'Websocket messages: ${controller.websocketMessageCount}',
                  ),
                  Text(
                    'Last websocket message: ${controller.lastSocketMessage.isEmpty ? '-' : controller.lastSocketMessage}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Live logs',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...controller.diagnostics.map(
            (DiagnosticEvent event) => Card(
              child: ListTile(
                dense: true,
                title: Text(event.type),
                subtitle: Text(
                  '${event.createdAt.toLocal()}\n${event.payload}',
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Backend recent events',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...controller.backendRecentEvents.map(
            (Map<String, dynamic> event) => Card(
              child: ListTile(
                dense: true,
                title: Text(event['type']?.toString() ?? 'event'),
                subtitle: Text(event.toString()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
