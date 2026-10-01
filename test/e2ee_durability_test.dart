import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/data/models/message_model.dart';
import 'package:secure_chat/data/services/decrypted_message_store.dart';
import 'package:secure_chat/data/services/e2ee/e2ee_service.dart';

class _UntrustedIdentityException implements Exception {}

class _NoSessionException implements Exception {}

class _InvalidMessageException implements Exception {}

class _InvalidMacException implements Exception {}

Message _signalMessage({
  required String id,
  String senderId = 'peer',
  String cipherBody = 'cipher',
}) {
  return Message(
    id: id,
    senderId: senderId,
    receiverId: 'me',
    messageType: 'text',
    content: '',
    status: 'sent',
    createdAt: DateTime.utc(2026, 1, 1),
    encryption: 'signal',
    cipherType: 1,
    cipherBody: cipherBody,
  );
}

Message _signalMediaMessage({required String id}) {
  return Message(
    id: id,
    senderId: 'peer',
    receiverId: 'me',
    messageType: 'image',
    content: '',
    filePath: '/api/files/media-1',
    status: 'sent',
    createdAt: DateTime.utc(2026, 1, 1),
    encryption: 'signal',
    cipherType: 1,
    cipherBody: 'cipher',
  );
}

void main() {
  group('DecryptedMessageStore', () {
    test('round-trips text and media records', () async {
      final persisted = <String, Map<String, DecryptedMessageRecord>>{};
      final store = DecryptedMessageStore(
        loadAll: (userId) async => persisted[userId] ?? {},
        saveAll: (userId, records) async {
          persisted[userId] = Map.of(records);
        },
      );

      await store.write(
        'me',
        'text-1',
        DecryptedMessageRecord(plaintext: 'hello durable'),
      );
      await store.write(
        'me',
        'media-1',
        DecryptedMessageRecord(
          plaintext: jsonEncode({'text': '', 'k': 'a2V5', 'iv': 'bm9uY2U'}),
          mediaKey: 'a2V5',
          mediaNonce: 'bm9uY2U',
        ),
      );

      final restarted = DecryptedMessageStore(
        loadAll: (userId) async => persisted[userId] ?? {},
        saveAll: (userId, records) async {
          persisted[userId] = Map.of(records);
        },
      );
      final text = await restarted.read('me', 'text-1');
      final media = await restarted.read('me', 'media-1');

      expect(text?.plaintext, 'hello durable');
      expect(media?.plaintext, contains('"k":"a2V5"'));
      expect(media?.mediaKey, 'a2V5');
      expect(media?.mediaNonce, 'bm9uY2U');
    });

    test('evicts the oldest records first', () async {
      final persisted = <String, Map<String, DecryptedMessageRecord>>{};
      final store = DecryptedMessageStore(
        loadAll: (userId) async => persisted[userId] ?? {},
        saveAll: (userId, records) async {
          persisted[userId] = Map.of(records);
        },
        maxEntries: 2,
      );

      await store.write(
        'me',
        'old',
        DecryptedMessageRecord(plaintext: 'old'),
      );
      await store.write(
        'me',
        'middle',
        DecryptedMessageRecord(plaintext: 'middle'),
      );
      await store.write(
        'me',
        'new',
        DecryptedMessageRecord(plaintext: 'new'),
      );

      expect(await store.read('me', 'old'), isNull);
      expect((await store.read('me', 'middle'))?.plaintext, 'middle');
      expect((await store.read('me', 'new'))?.plaintext, 'new');
    });

    test('unchanged rewrites do not touch persistence', () async {
      var saves = 0;
      final store = DecryptedMessageStore(
        loadAll: (_) async => {},
        saveAll: (_, __) async => saves++,
      );
      final record = DecryptedMessageRecord(plaintext: 'same');

      await store.write('me', 'same', record);
      await store.write('me', 'same', record);

      expect(saves, 1);
    });

    test('malformed records never load', () {
      expect(DecryptedMessageRecord.tryFromJson(null), isNull);
      expect(DecryptedMessageRecord.tryFromJson('nope'), isNull);
      expect(DecryptedMessageRecord.tryFromJson({'plaintext': 7}), isNull);
      expect(
        DecryptedMessageRecord.tryFromJson({
          'plaintext': 'ok',
          'media_key': 7,
        }),
        isNull,
      );
      expect(
        DecryptedMessageRecord.tryFromJson({
          'plaintext': 'ok',
          'saved_at': 'not-a-date',
        }),
        isNull,
      );
    });
  });

  group('E2EE durable decrypt', () {
    late E2eeService service;
    late Map<String, Map<String, DecryptedMessageRecord>> persisted;
    late int cipherCalls;
    late int rotations;

    setUp(() {
      service = E2eeService.instance;
      persisted = {};
      cipherCalls = 0;
      rotations = 0;
      service.debugLoadDecryptedMessages =
          (userId) async => persisted[userId] ?? {};
      service.debugSaveDecryptedMessages = (userId, records) async {
        persisted[userId] = Map.of(records);
      };
      service.debugRotatePeerIdentity = (_, __) async {
        rotations++;
        return true;
      };
      service.debugResetDecryptTestState();
    });

    test('a text decrypt survives a simulated restart', () async {
      service.debugDecryptCiphertext =
          (senderId, cipherType, cipherBody) async {
        cipherCalls++;
        return 'durable hello';
      };
      final message = _signalMessage(id: 'restart-text');

      final first = await service.decryptMessage(
        message,
        currentUserId: 'me',
      );
      expect(first.content, 'durable hello');
      expect(cipherCalls, 1);

      service.debugResetDecryptTestState();
      service.debugDecryptCiphertext =
          (senderId, cipherType, cipherBody) async {
        cipherCalls++;
        throw StateError('ratchet key already consumed');
      };

      final second = await service.decryptMessage(
        message,
        currentUserId: 'me',
      );
      expect(second.content, 'durable hello');
      expect(cipherCalls, 1);
    });

    test('a media envelope keeps its key across a restart', () async {
      const envelope = '{"text":"","k":"a2V5","iv":"bm9uY2U"}';
      service.debugDecryptCiphertext =
          (senderId, cipherType, cipherBody) async => envelope;
      final message = _signalMediaMessage(id: 'restart-media');

      final first = await service.decryptMessage(
        message,
        currentUserId: 'me',
      );
      expect(first.mediaKey, 'a2V5');
      expect(first.mediaNonce, 'bm9uY2U');

      service.debugResetDecryptTestState();
      service.debugDecryptCiphertext =
          (senderId, cipherType, cipherBody) async {
        throw StateError('ratchet key already consumed');
      };

      final second = await service.decryptMessage(
        message,
        currentUserId: 'me',
      );
      expect(second.mediaKey, 'a2V5');
      expect(second.mediaNonce, 'bm9uY2U');
    });

    test('group plaintext survives a simulated restart', () async {
      service.debugDecryptGroupCiphertext = (
              {required groupId,
              required senderId,
              required cipherBody,
              distributionB64}) async =>
          'durable group hello';
      final message = Message(
        id: 'group-restart',
        senderId: 'peer',
        receiverId: 'group-1',
        groupId: 'group-1',
        messageType: 'text',
        content: '',
        status: 'sent',
        createdAt: DateTime.utc(2026, 1, 1),
        encryption: 'sgkey',
        cipherType: 0,
        cipherBody: 'group-cipher',
      );

      final first = await service.decryptGroupMessage(
        message,
        currentUserId: 'me',
      );
      expect(first.content, 'durable group hello');

      service.debugResetDecryptTestState();
      service.debugDecryptGroupCiphertext = (
          {required groupId,
          required senderId,
          required cipherBody,
          distributionB64}) async {
        throw StateError('sender-key message already consumed');
      };

      final second = await service.decryptGroupMessage(
        message,
        currentUserId: 'me',
      );
      expect(second.content, 'durable group hello');
    });

    test('a MAC failure never rotates trust', () async {
      service.debugDecryptCiphertext =
          (senderId, cipherType, cipherBody) async {
        throw _InvalidMacException();
      };
      final message = _signalMessage(id: 'bad-mac');

      await service.decryptMessage(
        message,
        currentUserId: 'me',
        isLiveDelivery: true,
      );
      final second = await service.decryptMessage(
        message,
        currentUserId: 'me',
        isLiveDelivery: true,
      );

      expect(second.content, Message.decryptionFailedContent);
      expect(rotations, 0);
    });

    test('history failures never rotate trust', () async {
      service.debugDecryptCiphertext =
          (senderId, cipherType, cipherBody) async {
        throw _UntrustedIdentityException();
      };
      final message = _signalMessage(id: 'history-untrusted');

      await service.decryptMessage(message, currentUserId: 'me');
      await service.decryptMessage(message, currentUserId: 'me');
      await service.decryptMessage(
        message,
        currentUserId: 'me',
        isLiveDelivery: true,
      );

      expect(rotations, 0);
    });

    test('repeated live session failures rotate once', () async {
      service.debugDecryptCiphertext =
          (senderId, cipherType, cipherBody) async {
        cipherCalls++;
        throw _NoSessionException();
      };
      final message = _signalMessage(id: 'live-no-session');

      await service.decryptMessage(
        message,
        currentUserId: 'me',
        isLiveDelivery: true,
      );
      expect(rotations, 0);
      await service.decryptMessage(
        message,
        currentUserId: 'me',
        isLiveDelivery: true,
      );
      await service.decryptMessage(
        message,
        currentUserId: 'me',
        isLiveDelivery: true,
      );

      expect(cipherCalls, 3);
      expect(rotations, 1);
    });

    test('a success resets the live failure streak', () async {
      service.debugDecryptCiphertext =
          (senderId, cipherType, cipherBody) async {
        if (cipherBody == 'bad') throw _NoSessionException();
        return 'recovered';
      };

      await service.decryptMessage(
        _signalMessage(id: 'streak-bad', cipherBody: 'bad'),
        currentUserId: 'me',
        isLiveDelivery: true,
      );
      final good = await service.decryptMessage(
        _signalMessage(id: 'streak-good', cipherBody: 'good'),
        currentUserId: 'me',
        isLiveDelivery: true,
      );
      expect(good.content, 'recovered');
      await service.decryptMessage(
        _signalMessage(id: 'streak-bad-again', cipherBody: 'bad'),
        currentUserId: 'me',
        isLiveDelivery: true,
      );

      expect(rotations, 0);
    });

    test('only identity/session errors can arm recovery', () {
      E2eeIdentityRecoveryAction action(
        Object error, {
        bool isLiveDelivery = true,
      }) =>
          recoveryActionForDecryptError(
            error: error,
            consecutiveFailures: 3,
            isLiveDelivery: isLiveDelivery,
          );

      expect(action(_UntrustedIdentityException()),
          E2eeIdentityRecoveryAction.rotate);
      expect(action(_NoSessionException()), E2eeIdentityRecoveryAction.rotate);
      expect(
          action(_InvalidMessageException()), E2eeIdentityRecoveryAction.none);
      expect(action(_InvalidMacException()), E2eeIdentityRecoveryAction.none);
      expect(action(const FormatException('bad envelope')),
          E2eeIdentityRecoveryAction.none);
      expect(
        recoveryActionForDecryptError(
          error: _UntrustedIdentityException(),
          consecutiveFailures: 1,
          isLiveDelivery: true,
        ),
        E2eeIdentityRecoveryAction.none,
      );
      expect(
        action(_UntrustedIdentityException(), isLiveDelivery: false),
        E2eeIdentityRecoveryAction.none,
      );
    });
  });
}
