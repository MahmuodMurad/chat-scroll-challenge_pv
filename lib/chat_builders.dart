import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_image_message/flyer_chat_image_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';
import 'package:provider/provider.dart';

import 'chat_composer.dart';
import 'gemini_stream_manager.dart';

Builders createChatBuilders({
  required ScrollController scrollController,
  required NotificationListenerCallback<ScrollNotification>
      onScrollNotification,
  required String agentId,
  required Duration chunkAnimationDuration,
  required bool isStreaming,
  required VoidCallback onStopStreaming,
  required VoidCallback onRemoveStagedImage,
  required Uint8List? stagedImageBytes,
}) {
  return Builders(
    chatAnimatedListBuilder: (context, itemBuilder) {
      return NotificationListener<ScrollNotification>(
        onNotification: onScrollNotification,
        child: ChatAnimatedList(
          scrollController: scrollController,
          itemBuilder: itemBuilder,
        ),
      );
    },
    imageMessageBuilder: (
      context,
      message,
      index, {
      required bool isSentByMe,
      MessageGroupStatus? groupStatus,
    }) =>
        FlyerChatImageMessage(
      message: message,
      index: index,
      showTime: false,
      showStatus: false,
    ),
    composerBuilder: (context) => ChatComposer(
      isStreaming: isStreaming,
      onStop: onStopStreaming,
      stagedImageBytes: stagedImageBytes,
      onRemoveStagedImage: onRemoveStagedImage,
    ),
    textMessageBuilder: (
      context,
      message,
      index, {
      required bool isSentByMe,
      MessageGroupStatus? groupStatus,
    }) =>
        FlyerChatTextMessage(
      message: message,
      index: index,
      showTime: false,
      showStatus: false,
      receivedBackgroundColor: Colors.transparent,
      padding: message.authorId == agentId
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    textStreamMessageBuilder: (
      context,
      message,
      index, {
      required bool isSentByMe,
      MessageGroupStatus? groupStatus,
    }) {
      final streamState = context.watch<GeminiStreamManager>().getState(
            message.streamId,
          );
      return FlyerChatTextStreamMessage(
        message: message,
        index: index,
        streamState: streamState,
        chunkAnimationDuration: chunkAnimationDuration,
        showTime: false,
        showStatus: false,
        receivedBackgroundColor: Colors.transparent,
        padding: message.authorId == agentId
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      );
    },
  );
}
