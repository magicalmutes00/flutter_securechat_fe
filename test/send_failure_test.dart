import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/data/models/message_model.dart';
import 'package:secure_chat/data/services/e2ee/e2ee_service.dart';
import 'package:secure_chat/presentation/blocs/chat/chat_bloc.dart';
import 'package:secure_chat/presentation/blocs/chat/chat_event.dart';
import 'package:secure_chat/presentation/blocs/chat/chat_state.dart';

Message _message({String status = 'sent', String id = 'msg-1'}) {
  return Message(
    id: id,
    senderId: 'user-a',
    receiverId: 'user-b',
    messageType: 'image',
    content: '',
    filePath: '/tmp/photo.jpg',
    status: status,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('Message send states', () {
    test('isSending/isFailed only match their own status', () {
      expect(_message(status: 'sending').isSending, isTrue);
      expect(_message(status: 'sending').isFailed, isFalse);
      expect(_message(status: 'failed').isFailed, isTrue);
      expect(_message(status: 'failed').isSending, isFalse);
      expect(_message(status: 'sent').isFailed, isFalse);
      expect(_message(status: 'sent').isSending, isFalse);
    });

    test('failed status survives a toJson/fromJson round trip', () {
      final restored = Message.fromJson(_message(status: 'failed').toJson());
      expect(restored.isFailed, isTrue);
    });

    test('copyWith can flip a bubble to failed and back', () {
      final failed = _message(status: 'sending').copyWith(status: 'failed');
      expect(failed.isFailed, isTrue);
      expect(failed.copyWith(status: 'sent').isFailed, isFalse);
    });
  });

  group('ChatState.clearErrorMessage', () {
    test('copyWith without the flag preserves the error', () {
      const state = ChatState(errorMessage: 'boom');
      expect(state.copyWith().errorMessage, 'boom');
      expect(state.copyWith(status: ChatStatus.loaded).errorMessage, 'boom');
    });

    test('clearErrorMessage drops it while keeping everything else', () {
      const state = ChatState(
        status: ChatStatus.loaded,
        errorMessage: 'boom',
      );
      final cleared = state.copyWith(clearErrorMessage: true);
      expect(cleared.errorMessage, isNull);
      expect(cleared.status, ChatStatus.loaded);
    });

    test('an explicit error still wins when the flag is absent', () {
      const state = ChatState();
      expect(
        state.copyWith(errorMessage: 'net down').errorMessage,
        'net down',
      );
    });
  });

  group('ChatRetrySend', () {
    test('carries the temp id and compares by value', () {
      const a = ChatRetrySend(tempId: 'temp_1');
      const b = ChatRetrySend(tempId: 'temp_1');
      const c = ChatRetrySend(tempId: 'temp_2');
      expect(a, b);
      expect(a == c, isFalse);
    });

    test('ChatClearError compares by value', () {
      expect(const ChatClearError(), const ChatClearError());
    });
  });

  group('sendFailureReason', () {
    test('oversize wording for 413 and too-large text', () {
      expect(
        sendFailureReason(Exception('DioException: status code of 413')),
        'That file is too large to send.',
      );
      expect(
        sendFailureReason(Exception('File size exceeds maximum allowed size')),
        'That file is too large to send.',
      );
    });

    test('offline wording for connectivity failures', () {
      expect(
        sendFailureReason(Exception('SocketException: Failed host lookup')),
        contains('No connection'),
      );
      expect(
        sendFailureReason(Exception('Connection reset by peer')),
        contains('No connection'),
      );
      expect(
        sendFailureReason(Exception('send timeout')),
        contains('No connection'),
      );
    });

    test('encryption failures surface their own message', () {
      const e = E2eeEncryptionException('Attachment not sent: no session');
      expect(sendFailureReason(e), 'Attachment not sent: no session');
    });

    test('anything else gets the generic retry wording', () {
      expect(
        sendFailureReason(Exception('Cloudinary upload failed: Invalid')),
        contains('Tap it to retry'),
      );
    });
  });
}
