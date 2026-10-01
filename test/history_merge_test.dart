import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/data/models/message_model.dart';
import 'package:secure_chat/presentation/blocs/chat/chat_bloc.dart';

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
    encryption: 'none',
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

    test('known-good rows survive failed re-decrypts', () {
      final cached = [
        _row(
          id: 'good',
          content: 'already decrypted',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];
      final page = [
        _row(
          id: 'good',
          content: Message.decryptionFailedContent,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];

      final merged = mergeHistoryMessages(cached, page);

      expect(merged.single.content, 'already decrypted');
    });

    test('a fresh decrypt repairs a stuck placeholder', () {
      final cached = [
        _row(
          id: 'healed',
          content: Message.decryptionFailedContent,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];
      final page = [
        _row(
          id: 'healed',
          content: 'decrypted this time',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];

      final merged = mergeHistoryMessages(cached, page);

      expect(merged.single.content, 'decrypted this time');
    });
  });
}
