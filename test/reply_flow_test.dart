import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/data/models/message_model.dart';
import 'package:secure_chat/presentation/widgets/ui/quote_strip.dart';

Message _textMessage({String? replyToId, String content = 'hello'}) {
  return Message(
    id: 'msg-1',
    senderId: 'user-a',
    receiverId: 'user-b',
    messageType: 'text',
    content: content,
    replyToId: replyToId,
    status: 'sent',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('Message.replyToId serialization', () {
    test('reply_to_id survives a toJson/fromJson round trip', () {
      final message = _textMessage(replyToId: 'quoted-id-123');
      final restored = Message.fromJson(message.toJson());
      expect(restored.replyToId, 'quoted-id-123');
    });

    test('legacy payloads without the key parse to null', () {
      final json = _textMessage().toJson()..remove('reply_to_id');
      final restored = Message.fromJson(json);
      expect(restored.replyToId, isNull);
    });

    test('copyWith preserves the reply link unless overridden', () {
      final message = _textMessage(replyToId: 'quoted-id-123');
      expect(message.copyWith(content: 'edited').replyToId, 'quoted-id-123');
      expect(message.copyWith(replyToId: 'other').replyToId, 'other');
    });

    test('equality distinguishes different reply targets', () {
      final a = _textMessage(replyToId: 'x');
      final b = _textMessage(replyToId: 'y');
      final c = _textMessage(replyToId: 'x');
      expect(a == b, isFalse);
      expect(a == c, isTrue);
    });
  });

  group('ReplySnippet.forMessage', () {
    test('text uses content, empty text is unavailable', () {
      expect(ReplySnippet.forMessage(_textMessage()).text, 'hello');
      expect(ReplySnippet.forMessage(_textMessage(content: '  ')).text,
          'Message unavailable');
    });

    test('media types render labels with icons', () {
      Message media(String type, {String? fileName}) => Message(
            id: 'm',
            senderId: 'a',
            receiverId: 'b',
            messageType: type,
            content: '',
            fileName: fileName,
            status: 'sent',
            createdAt: DateTime.utc(2026, 1, 1),
          );
      expect(ReplySnippet.forMessage(media('image')).text, 'Photo');
      expect(ReplySnippet.forMessage(media('video')).text, 'Video');
      expect(
          ReplySnippet.forMessage(media('audio', fileName: 'a.m4a')).text,
          'a.m4a');
      expect(
          ReplySnippet.forMessage(media('document', fileName: 'd.pdf')).text,
          'd.pdf');
      expect(ReplySnippet.forMessage(media('image')).icon, isNotNull);
      expect(ReplySnippet.forMessage(_textMessage()).icon, isNull);
    });
  });
}
