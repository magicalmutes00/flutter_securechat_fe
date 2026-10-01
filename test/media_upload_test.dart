import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/core/constants/app_constants.dart';
import 'package:secure_chat/data/models/message_model.dart';
import 'package:secure_chat/data/services/media_preparation_service.dart';
import 'package:secure_chat/presentation/blocs/chat/chat_bloc.dart';
import 'package:secure_chat/presentation/blocs/chat/chat_state.dart';

Message _message() {
  return Message(
    id: 'msg-1',
    senderId: 'user-a',
    receiverId: 'user-b',
    messageType: 'image',
    content: '',
    status: 'sending',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('MediaPreparationService.validate', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('media_upload_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<String> makeFile(String name, int bytes) async {
      final file = File('${tmp.path}/$name');
      await file.writeAsBytes(List<int>.filled(bytes, 7));
      return file.path;
    }

    test('accepts a small jpg photo', () async {
      final path = await makeFile('photo.jpg', 1024);
      await MediaPreparationService.validate(
        filePath: path,
        messageType: AppConstants.messageTypeImage,
      );
    });

    test('rejects an oversize photo without uploading', () async {
      final path = await makeFile(
        'huge.jpg',
        AppConstants.maxImageSizeMB * 1024 * 1024 + 1,
      );
      expect(
        () => MediaPreparationService.validate(
          filePath: path,
          messageType: AppConstants.messageTypeImage,
        ),
        throwsA(isA<MediaValidationException>().having(
          (e) => e.message,
          'message',
          contains('too large'),
        )),
      );
    });

    test('rejects an extension outside the server allow-list', () async {
      final path = await makeFile('notes.exe', 16);
      expect(
        () => MediaPreparationService.validate(
          filePath: path,
          messageType: AppConstants.messageTypeImage,
        ),
        throwsA(isA<MediaValidationException>()),
      );
    });

    test('heic gets its own actionable message', () async {
      final path = await makeFile('photo.heic', 16);
      expect(
        () => MediaPreparationService.validate(
          filePath: path,
          messageType: AppConstants.messageTypeImage,
        ),
        throwsA(isA<MediaValidationException>().having(
          (e) => e.message,
          'message',
          contains('heic'),
        )),
      );
    });

    test('rejects a missing file', () async {
      expect(
        () => MediaPreparationService.validate(
          filePath: '${tmp.path}/gone.jpg',
          messageType: AppConstants.messageTypeImage,
        ),
        throwsA(isA<MediaValidationException>()),
      );
    });

    test('type-specific caps apply per category', () {
      expect(
        MediaPreparationService.maxSizeBytes(AppConstants.messageTypeImage),
        AppConstants.maxImageSizeMB * 1024 * 1024,
      );
      expect(
        MediaPreparationService.maxSizeBytes(AppConstants.messageTypeVideo),
        AppConstants.maxVideoSizeMB * 1024 * 1024,
      );
      expect(
        MediaPreparationService.maxSizeBytes(AppConstants.messageTypeDocument),
        AppConstants.maxDocumentSizeMB * 1024 * 1024,
      );
    });
  });

  group('Message.uploadProgress', () {
    test('defaults to null and never serializes', () {
      final message = _message().copyWith(uploadProgress: 0.4);
      expect(message.uploadProgress, 0.4);
      expect(message.toJson().containsKey('upload_progress'), isFalse);
      expect(Message.fromJson(message.toJson()).uploadProgress, isNull);
    });

    test('clearUploadProgress drops it while keeping other fields', () {
      final message =
          _message().copyWith(uploadProgress: 0.4, status: 'failed');
      final cleared =
          message.copyWith(status: 'sent', clearUploadProgress: true);
      expect(cleared.uploadProgress, isNull);
      expect(cleared.isFailed, isFalse);
    });

    test('progress ticks change equality so the bubble rebuilds', () {
      final a = _message().copyWith(uploadProgress: 0.1);
      final b = _message().copyWith(uploadProgress: 0.2);
      expect(a == b, isFalse);
    });
  });

  group('ChatState.pendingUploads', () {
    test('defaults to zero and copies through', () {
      const state = ChatState();
      expect(state.pendingUploads, 0);
      expect(state.copyWith().pendingUploads, 0);
      expect(
        state.copyWith(pendingUploads: 2).pendingUploads,
        2,
      );
    });
  });

  group('sendFailureReason', () {
    test('validation failures surface their own message', () {
      const e = MediaValidationException('That photo is too large (max 10 MB).');
      expect(
        sendFailureReason(e),
        'That photo is too large (max 10 MB).',
      );
    });
  });
}
