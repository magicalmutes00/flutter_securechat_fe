import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/core/constants/app_constants.dart';
import 'package:secure_chat/data/models/message_model.dart';
import 'package:secure_chat/data/services/e2ee/e2ee_service.dart';

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
  group('discardStagedPlaintext', () {
    test('drops only the most recently staged envelope', () {
      final svc = E2eeService.instance;
      svc.stageOwnPlaintext('peer-discard-1', 'A');
      svc.stageOwnPlaintext('peer-discard-1', 'B');
      svc.discardStagedPlaintext('peer-discard-1');
      expect(svc.commitOwnPlaintext('srv-1', 'peer-discard-1'), 'A');
    });

    test('empty-queue discard and commit are safe no-ops', () {
      final svc = E2eeService.instance;
      svc.discardStagedPlaintext('peer-discard-2');
      expect(svc.commitOwnPlaintext('srv-2', 'peer-discard-2'), isNull);
    });

    test('a dead send cannot poison the next ack', () {
      // A is staged, its socket dies (discarded), B is staged, B's ack
      // arrives: it must commit B, not the dead A.
      final svc = E2eeService.instance;
      svc.stageOwnPlaintext('peer-discard-3', 'dead-envelope');
      svc.discardStagedPlaintext('peer-discard-3');
      svc.stageOwnPlaintext('peer-discard-3', 'live-envelope');
      expect(
        svc.commitOwnPlaintext('srv-3', 'peer-discard-3'),
        'live-envelope',
      );
    });
  });

  group('outbox text-only contract', () {
    test('queued entries keep their type through JSON', () {
      // _flushOutbox reads messageType off deserialized outbox entries to
      // route text vs attachments; the type must survive the round trip.
      final restored = Message.fromJson(
        jsonDecode(jsonEncode(_fileMessage().toJson())) as Map<String, dynamic>,
      );
      expect(restored.messageType, AppConstants.messageTypeImage);
      expect(
        restored.messageType == AppConstants.messageTypeText,
        isFalse,
      );
    });
  });
}
