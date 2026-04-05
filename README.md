# Chat Scroll Challenge

Flutter chat demo focused on fixing auto-scroll behavior for streaming AI responses.

## UX Issues Identified And Fixed

1. Streaming responses were not followed smoothly.
   Fix: Auto-scroll now runs through a queued follow-to-bottom pass instead of starting a new animation on every token, which makes streaming feel more stable and less jittery.

2. The list fought the user while they were reading older messages.
   Fix: Manual scrolling away from the bottom immediately disables auto-scroll, so new chunks and message updates no longer pull the list down unexpectedly.

3. Auto-scroll did not reliably resume after the user returned to the bottom.
   Fix: Reaching the bottom again now re-enables auto-scroll and triggers a fresh follow pass immediately, so streaming resumes correctly without waiting for an extra event.

4. Bottom detection was too fragile.
   Fix: The app now uses a bottom threshold instead of exact equality with `maxScrollExtent`, which is more reliable during incremental streaming and layout changes.

5. Streaming growth and normal message updates were handled inconsistently.
   Fix: Auto-scroll is triggered from both chat operations and streaming layout changes, so it works when a streamed bubble is inserted and while that bubble continues to grow.

6. Sending a new message could leave the latest content off-screen.
   Fix: User sends now force the list back to the bottom immediately so the sent message and streamed reply remain visible.

7. Image attachments were sent too early.
   Fix: Images are now staged in the composer with a preview and are only sent when the user explicitly submits.

8. Keyboard behavior was backwards for multiline input.
   Fix: `Enter` now sends the message, while `Shift+Enter` inserts a newline.

## Deployed URL

Temporary placeholder: `https://example.com/chat-scroll-demo`

## Screen Recording

Temporary placeholder: `https://example.com/chat-scroll-recording`

## Current Structure

The main screen was cleaned up and split into smaller files:

- `lib/gemini_chat_screen.dart`
  Coordinates Gemini streaming, message insertion, staged attachments, and top-level chat state.
- `lib/chat_auto_scroll_controller.dart`
  Encapsulates bottom detection, pause/resume logic, and queued scroll scheduling.
- `lib/chat_builders.dart`
  Holds the `flutter_chat_ui` builder configuration for the animated list, composer, and message widgets.
- `lib/chat_composer.dart`
  Contains the composer UI, staged image preview, submit handling, and composer height measurement.
- `lib/gemini_stream_manager.dart`
  Manages incremental stream state and final conversion from `TextStreamMessage` to `TextMessage`.
- `lib/in_memory_chat_controller.dart`
  Provides the in-memory message store used by the chat UI.
