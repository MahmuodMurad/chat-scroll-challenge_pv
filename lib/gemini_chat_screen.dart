import 'dart:async';
import 'dart:typed_data';

import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart'
    hide InMemoryChatController;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'chat_auto_scroll_controller.dart';
import 'chat_builders.dart';
import 'gemini_stream_manager.dart';
import 'in_memory_chat_controller.dart';

const Duration _kChunkAnimationDuration = Duration(milliseconds: 350);

class GeminiChatScreen extends StatefulWidget {
  final String geminiApiKey;

  const GeminiChatScreen({super.key, required this.geminiApiKey});

  @override
  State<GeminiChatScreen> createState() => _GeminiChatScreenState();
}

class _GeminiChatScreenState extends State<GeminiChatScreen>
    with WidgetsBindingObserver {
  final _uuid = const Uuid();
  final _crossCache = CrossCache();
  final _scrollController = ScrollController();
  final _chatController = InMemoryChatController();

  final _currentUser = const User(id: 'me');
  final _agent = const User(id: 'agent');

  late final GenerativeModel _model;
  late ChatSession _chatSession;
  late final GeminiStreamManager _streamManager;
  late final ChatAutoScrollController _autoScrollController;

  bool _isStreaming = false;
  StreamSubscription? _currentStreamSubscription;
  String? _currentStreamId;
  StreamSubscription<ChatOperation>? _chatOperationsSubscription;

  // Staged image (set by attachment picker, cleared on send/cancel).
  String? _stagedImagePath;
  Uint8List? _stagedImageBytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _streamManager = GeminiStreamManager(
      chatController: _chatController,
      chunkAnimationDuration: _kChunkAnimationDuration,
    );
    _autoScrollController = ChatAutoScrollController(
      scrollController: _scrollController,
    );

    _model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: widget.geminiApiKey,
      safetySettings: [
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
      ],
    );

    _chatSession = _model.startChat();
    _scrollController.addListener(_autoScrollController.handleScrollControllerChanged);
    _streamManager.addListener(_handleStreamingLayoutChanged);
    _chatOperationsSubscription = _chatController.operationsStream.listen(
      _handleChatOperation,
    );
  }

  @override
  void didChangeMetrics() {
    _autoScrollController.handleMetricsChanged();
  }

  @override
  void dispose() {
    _currentStreamSubscription?.cancel();
    _chatOperationsSubscription?.cancel();
    _streamManager.removeListener(_handleStreamingLayoutChanged);
    _scrollController.removeListener(
      _autoScrollController.handleScrollControllerChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    _streamManager.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    _crossCache.dispose();
    super.dispose();
  }

  void _handleChatOperation(ChatOperation operation) {
    switch (operation.type) {
      case ChatOperationType.insert:
      case ChatOperationType.insertAll:
      case ChatOperationType.update:
      case ChatOperationType.set:
        _autoScrollController.scheduleAutoScroll();
        return;
      case ChatOperationType.remove:
        return;
    }
  }

  void _handleStreamingLayoutChanged() {
    _autoScrollController.scheduleAutoScroll();
  }

  void _forceScrollToBottom() {
    _autoScrollController.forceScrollToBottom();
  }

  void _stopCurrentStream() {
    if (_currentStreamSubscription != null && _currentStreamId != null) {
      _currentStreamSubscription!.cancel();
      _currentStreamSubscription = null;

      setState(() {
        _isStreaming = false;
      });

      if (_currentStreamId != null) {
        _streamManager.errorStream(
          _currentStreamId!,
          'Stream stopped by user',
        );
        _currentStreamId = null;
      }
    }
  }

  void _handleStreamError(
    String streamId,
    dynamic error,
    TextStreamMessage? streamMessage,
  ) async {
    debugPrint('Generation error for $streamId: $error');

    if (streamMessage != null) {
      await _streamManager.errorStream(streamId, error);
    }

    if (mounted) {
      setState(() {
        _isStreaming = false;
      });
    }
    _currentStreamSubscription = null;
    _currentStreamId = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Gemini Chat')),
      body: ChangeNotifierProvider.value(
        value: _streamManager,
        child: Chat(
          builders: createChatBuilders(
            scrollController: _scrollController,
            onScrollNotification: _autoScrollController.handleScrollNotification,
            agentId: _agent.id,
            chunkAnimationDuration: _kChunkAnimationDuration,
            isStreaming: _isStreaming,
            onStopStreaming: _stopCurrentStream,
            onRemoveStagedImage: _clearStagedImage,
            stagedImageBytes: _stagedImageBytes,
          ),
          chatController: _chatController,
          crossCache: _crossCache,
          currentUserId: _currentUser.id,
          onAttachmentTap: _handleAttachmentTap,
          onMessageSend: _handleMessageSend,
          resolveUser: (id) => Future.value(
            switch (id) {
              'me' => _currentUser,
              'agent' => _agent,
              _ => null,
            },
          ),
          theme: ChatTheme.fromThemeData(theme),
        ),
      ),
    );
  }

  void _handleMessageSend(String text) async {
    final hasImage = _stagedImagePath != null && _stagedImageBytes != null;

    if (!hasImage && text.isEmpty) return;

    if (hasImage) {
      await _chatController.insertMessage(
        ImageMessage(
          id: _uuid.v4(),
          authorId: _currentUser.id,
          createdAt: DateTime.now().toUtc(),
          source: _stagedImagePath!,
        ),
      );
    }

    if (text.isNotEmpty) {
      await _chatController.insertMessage(
        TextMessage(
          id: _uuid.v4(),
          authorId: _currentUser.id,
          createdAt: DateTime.now().toUtc(),
          text: text,
          metadata: isOnlyEmoji(text) ? {'isOnlyEmoji': true} : null,
        ),
      );
    }

    // Local sends should pin the chat back to the latest content immediately.
    _forceScrollToBottom();

    final Content content;
    if (hasImage && text.isNotEmpty) {
      content = Content.multi([
        DataPart('image/jpeg', _stagedImageBytes!),
        TextPart(text),
      ]);
    } else if (hasImage) {
      content = Content.data('image/jpeg', _stagedImageBytes!);
    } else {
      content = Content.text(text);
    }

    _clearStagedImage();
    _sendContent(content);
  }

  void _clearStagedImage() {
    setState(() {
      _stagedImagePath = null;
      _stagedImageBytes = null;
    });
  }

  // Pick an image and stage it for the next send without submitting yet.
  void _handleAttachmentTap() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    await _crossCache.downloadAndSave(image.path);
    final bytes = await _crossCache.get(image.path);

    setState(() {
      _stagedImagePath = image.path;
      _stagedImageBytes = bytes;
    });
  }

  void _sendContent(Content content) async {
    final streamId = _uuid.v4();
    _currentStreamId = streamId;
    TextStreamMessage? streamMessage;

    var messageInserted = false;

    setState(() {
      _isStreaming = true;
    });

    Future<void> createAndInsertMessage() async {
      if (messageInserted || !mounted) return;
      messageInserted = true;

      streamMessage = TextStreamMessage(
        id: streamId,
        authorId: _agent.id,
        createdAt: DateTime.now().toUtc(),
        streamId: streamId,
      );
      await _chatController.insertMessage(streamMessage!);
      _streamManager.startStream(streamId, streamMessage!);
    }

    try {
      final response = _chatSession.sendMessageStream(content);

      _currentStreamSubscription = response.listen(
        (chunk) async {
          if (chunk.text != null) {
            final textChunk = chunk.text!;
            if (textChunk.isEmpty) return;

            if (!messageInserted) {
              await createAndInsertMessage();
            }

            if (streamMessage == null) return;

            _streamManager.addChunk(streamId, textChunk);
          }
        },
        onDone: () async {
          if (streamMessage != null) {
            await _streamManager.completeStream(streamId);
          }

          if (mounted) {
            setState(() {
              _isStreaming = false;
            });
          }
          _currentStreamSubscription = null;
          _currentStreamId = null;
        },
        onError: (error) async {
          _handleStreamError(streamId, error, streamMessage);
        },
      );
    } catch (error) {
      _handleStreamError(streamId, error, streamMessage);
    }
  }
}
