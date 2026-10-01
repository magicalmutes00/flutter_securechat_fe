import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/core/constants/app_constants.dart';
import 'package:secure_chat/data/models/message_model.dart';

Message _textMessage({String id = 'msg-1', String content = 'hello'}) {
  return Message(
    id: id,
    senderId: 'user-a',
    receiverId: 'user-b',
    messageType: AppConstants.messageTypeText,
    content: content,
    status: 'sending',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

Message _fileMessage() {
  return Message(
    id: 'msg-1',
    senderId: 'user-a',
    receiverId: 'user-b',
    messageType: AppConstants.messageTypeImage,
    content: '',
    filePath: '/tmp/photo.jpg',
    status: 'sending',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('outbox text-only contract', () {
    test('queued text keeps content through JSON', () {
      final restored = Message.fromJson(
        jsonDecode(jsonEncode(_textMessage().toJson())) as Map<String, dynamic>,
      );
      expect(restored.messageType, AppConstants.messageTypeText);
      expect(restored.content, 'hello');
    });

    test('queued entries keep their type through JSON', () {
      // The outbox flush reads messageType off deserialized entries to route
      // text vs attachments; the type must survive the round trip.
      final restored = Message.fromJson(
        jsonDecode(jsonEncode(_fileMessage().toJson())) as Map<String, dynamic>,
      );
      expect(restored.messageType, AppConstants.messageTypeImage);
      expect(
        restored.messageType == AppConstants.messageTypeText,
        isFalse,
      );
    });

    test('outbox payloads never carry crypto wire fields', () {
      final json =
          jsonDecode(jsonEncode(_textMessage().toJson())) as Map<String, dynamic>;
      expect(json.containsKey('cipher_type'), isFalse);
      expect(json.containsKey('cipher_body'), isFalse);
      expect(json.containsKey('distribution'), isFalse);
      expect(json.containsKey('encryption'), isFalse);
    });
  });
}
