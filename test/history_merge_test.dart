import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/core/theme/app_colors.dart';
import 'package:secure_chat/data/models/message_model.dart';
import 'package:secure_chat/presentation/blocs/chat/chat_bloc.dart';
import 'package:secure_chat/presentation/widgets/attachment_image.dart';
import 'package:secure_chat/presentation/widgets/message_bubble.dart';

Message _row({
  required String id,
  required String content,
  required DateTime createdAt,
}) {
  return Message(
    id: id,
    senderId: 'peer',
    receiverId: 'me',
    messageType: 'text',
    content: content,
    status: 'sent',
    createdAt: createdAt,
  );
}

void main() {
  group('mergeHistoryMessages', () {
    test('a fetched page cannot discard older cached rows', () {
      final cached = [
        _row(
          id: 'old',
          content: 'older than this page',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        _row(
          id: 'current',
          content: 'current page',
          createdAt: DateTime.utc(2026, 1, 2),
        ),
      ];
      final page = [
        _row(
          id: 'current',
          content: 'current page',
          createdAt: DateTime.utc(2026, 1, 2),
        ),
      ];

      final merged = mergeHistoryMessages(cached, page);

      expect(merged.map((message) => message.id), ['old', 'current']);
    });

    test('cached rows win over identical incoming rows', () {
      final cached = [
        _row(
          id: 'keep',
          content: 'cached copy',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];
      final page = [
        _row(
          id: 'keep',
          content: 'server copy',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];

      final merged = mergeHistoryMessages(cached, page);

      expect(merged.single.content, 'cached copy');
    });

    test('an empty cached row is healed by incoming content', () {
      final cached = [
        _row(
          id: 'healed',
          content: '',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];
      final page = [
        _row(
          id: 'healed',
          content: 'arrived late',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];

      final merged = mergeHistoryMessages(cached, page);

      expect(merged.single.content, 'arrived late');
    });

    test('merged output is chronological', () {
      final cached = [
        _row(
          id: 'new',
          content: 'newer',
          createdAt: DateTime.utc(2026, 1, 3),
        ),
      ];
      final page = [
        _row(
          id: 'old',
          content: 'older',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];

      final merged = mergeHistoryMessages(cached, page);

      expect(merged.map((m) => m.id), ['old', 'new']);
    });
  });

  group('legacy encryption marker', () {
    test('empty content with a marker maps to the legacy notice', () {
      final restored = Message.fromJson(const {
        'id': 'legacy-1',
        'sender_id': 'peer',
        'receiver_id': 'me',
        'message_type': 'text',
        'content': '',
        'status': 'sent',
        'created_at': '2026-01-01T00:00:00.000Z',
        'encryption': 'signal',
      });
      expect(restored.content, Message.legacyEncryptedNotice);
      expect(restored.isLegacyNotice, isTrue);
    });

    test('plaintext rows never become the legacy notice', () {
      final restored = Message.fromJson(const {
        'id': 'plain-1',
        'sender_id': 'peer',
        'receiver_id': 'me',
        'message_type': 'text',
        'content': 'hello',
        'status': 'sent',
        'created_at': '2026-01-01T00:00:00.000Z',
        'encryption': 'none',
      });
      expect(restored.content, 'hello');
      expect(restored.isLegacyNotice, isFalse);
    });

    test('wire-only crypto fields are ignored on parse', () {
      final restored = Message.fromJson(const {
        'id': 'legacy-2',
        'sender_id': 'peer',
        'receiver_id': 'me',
        'message_type': 'text',
        'content': '',
        'status': 'sent',
        'created_at': '2026-01-01T00:00:00.000Z',
        'encryption': 'sgkey',
        'cipher_type': 3,
        'cipher_body': 'aGVsbG8=',
        'distribution': 'ZGlzdA==',
      });
      expect(restored.content, Message.legacyEncryptedNotice);
    });

    testWidgets('legacy media history shows the notice, not a decoder', (
      tester,
    ) async {
      final restored = Message.fromJson(const {
        'id': 'legacy-media',
        'sender_id': 'peer',
        'receiver_id': 'me',
        'message_type': 'image',
        'content': '',
        'file_path': '/api/files/legacy-media',
        'status': 'sent',
        'created_at': '2026-01-01T00:00:00.000Z',
        'encryption': 'signal',
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light()]),
          home: Scaffold(
            body: MessageBubble(message: restored, isMe: false),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(Message.legacyEncryptedNotice), findsOneWidget);
      expect(find.byType(AttachmentImage), findsNothing);
    });
  });
}
