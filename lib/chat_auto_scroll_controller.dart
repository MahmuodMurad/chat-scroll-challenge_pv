import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ChatAutoScrollController {
  ChatAutoScrollController({
    required ScrollController scrollController,
    this.bottomThreshold = 40,
    this.jumpThreshold = 120,
  }) : _scrollController = scrollController;

  final ScrollController _scrollController;
  final double bottomThreshold;
  final double jumpThreshold;

  bool _userIsInteractingWithScroll = false;
  bool _isAtBottom = true;
  bool _shouldAutoScroll = true;
  bool _autoScrollScheduled = false;
  bool _autoScrollRunning = false;
  bool _needsAutoScrollAfterCurrentPass = false;

  void handleMetricsChanged() {
    if (_shouldAutoScroll) {
      scheduleAutoScroll();
    }
  }

  void handleScrollControllerChanged() {
    if (!_scrollController.hasClients) return;

    final wasAtBottom = _isAtBottom;
    final isAtBottomNow = _isNearBottom(_scrollController.position);
    _isAtBottom = isAtBottomNow;

    if (isAtBottomNow) {
      _shouldAutoScroll = true;
      if (!wasAtBottom) {
        scheduleAutoScroll();
      }
    }
  }

  bool handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;

    final wasAtBottom = _isAtBottom;
    final isAtBottomNow = _isNearBottom(notification.metrics);
    _isAtBottom = isAtBottomNow;

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userIsInteractingWithScroll = true;
      if (!isAtBottomNow) {
        _shouldAutoScroll = false;
      }
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _userIsInteractingWithScroll = true;
      if (!isAtBottomNow) {
        _shouldAutoScroll = false;
      }
    } else if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle &&
        !isAtBottomNow) {
      _userIsInteractingWithScroll = true;
      _shouldAutoScroll = false;
    } else if (notification is ScrollEndNotification) {
      _userIsInteractingWithScroll = false;
      if (isAtBottomNow) {
        _shouldAutoScroll = true;
        scheduleAutoScroll();
      }
    }

    if (isAtBottomNow) {
      _shouldAutoScroll = true;
      if (!wasAtBottom) {
        scheduleAutoScroll();
      }
    }

    return false;
  }

  void forceScrollToBottom() {
    _shouldAutoScroll = true;
    _isAtBottom = true;
    scheduleAutoScroll(forceJump: true);
  }

  void scheduleAutoScroll({bool forceJump = false}) {
    if ((!_shouldAutoScroll && !forceJump) || _autoScrollScheduled) return;

    if (_autoScrollRunning) {
      _needsAutoScrollAfterCurrentPass = true;
      return;
    }

    _autoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _autoScrollScheduled = false;

      if (!_scrollController.hasClients) return;
      if ((!_shouldAutoScroll && !forceJump) || _userIsInteractingWithScroll) {
        return;
      }

      final position = _scrollController.position;
      final targetOffset = position.maxScrollExtent;
      final distanceToBottom = targetOffset - position.pixels;

      if (distanceToBottom <= bottomThreshold) {
        _setAtBottom(true);
        return;
      }

      _autoScrollRunning = true;

      try {
        if (forceJump || distanceToBottom >= jumpThreshold) {
          _scrollController.jumpTo(targetOffset);
        } else {
          await _scrollController.animateTo(
            targetOffset,
            duration: _autoScrollDurationFor(distanceToBottom),
            curve: Curves.easeOut,
          );
        }
      } catch (_) {
        // User gestures can interrupt an animation; that should win.
      } finally {
        _autoScrollRunning = false;
        if (_scrollController.hasClients) {
          _setAtBottom(_isNearBottom(_scrollController.position));
        }

        if (_needsAutoScrollAfterCurrentPass) {
          _needsAutoScrollAfterCurrentPass = false;
          scheduleAutoScroll();
        }
      }
    });
  }

  void _setAtBottom(bool value) {
    if (_isAtBottom == value) return;
    _isAtBottom = value;
  }

  bool _isNearBottom(ScrollMetrics metrics) {
    if (!metrics.hasPixels) return true;
    return (metrics.maxScrollExtent - metrics.pixels) <= bottomThreshold;
  }

  Duration _autoScrollDurationFor(double distanceToBottom) {
    final clampedDistance = math.max(0, distanceToBottom);
    final milliseconds =
        (80 + (clampedDistance * 0.45)).round().clamp(80, 160);
    return Duration(milliseconds: milliseconds);
  }
}
