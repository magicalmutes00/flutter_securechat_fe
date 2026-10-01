import 'dart:io';

import '../../core/constants/app_constants.dart';

/// Thrown when a picked file must not be uploaded. Carries the exact line
/// the UI shows — validation runs on-device before any encryption or upload
/// work, so these rejections are instant and free.
class MediaValidationException implements Exception {
  const MediaValidationException(this.message);

  final String message;

  @override
  String toString() => 'MediaValidationException: $message';
}

/// Pre-flight checks for outgoing attachments. Mirrors the server's
/// extension allow-list and the app's per-type size caps so doomed uploads
/// fail here — instantly — instead of after a full encrypt + upload cycle.
class MediaPreparationService {
  MediaPreparationService._();

  /// Must stay in sync with the backend's `allowedFileExtensions`.
  /// 'enc' covers ciphertext paths; HEIC/HEIF are absent on purpose — the
  /// server rejects them, so they fail here with an actionable message
  /// instead of a bare 400 after uploading megabytes.
  static const Map<String, List<String>> allowedExtensions = {
    AppConstants.messageTypeImage: [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'enc'
    ],
    AppConstants.messageTypeVideo: [
      'mp4',
      'mov',
      'avi',
      'mkv',
      'webm',
      'enc'
    ],
    AppConstants.messageTypeAudio: [
      'mp3',
      'wav',
      'aac',
      'm4a',
      'ogg',
      'enc'
    ],
    AppConstants.messageTypeDocument: [
      'pdf',
      'doc',
      'docx',
      'txt',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'enc'
    ],
  };

  static int maxSizeBytes(String messageType) {
    switch (messageType) {
      case AppConstants.messageTypeImage:
        return AppConstants.maxImageSizeMB * 1024 * 1024;
      case AppConstants.messageTypeVideo:
        return AppConstants.maxVideoSizeMB * 1024 * 1024;
      case AppConstants.messageTypeAudio:
        return AppConstants.maxAudioSizeMB * 1024 * 1024;
      case AppConstants.messageTypeDocument:
        return AppConstants.maxDocumentSizeMB * 1024 * 1024;
      default:
        return AppConstants.maxDocumentSizeMB * 1024 * 1024;
    }
  }

  static String _label(String messageType) {
    switch (messageType) {
      case AppConstants.messageTypeImage:
        return 'photo';
      case AppConstants.messageTypeVideo:
        return 'video';
      case AppConstants.messageTypeAudio:
        return 'audio file';
      case AppConstants.messageTypeDocument:
        return 'document';
      default:
        return 'file';
    }
  }

  /// Throws [MediaValidationException] when the file at [filePath] must not
  /// be uploaded as [messageType].
  static Future<void> validate({
    required String filePath,
    required String messageType,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const MediaValidationException(
          'That file is no longer available.');
    }
    final name = filePath.split('/').last.split('\\').last;
    final dot = name.lastIndexOf('.');
    final extension = dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
    final allowed = allowedExtensions[messageType];
    if (allowed == null || !allowed.contains(extension)) {
      if (extension == 'heic' || extension == 'heif') {
        throw MediaValidationException(
          'iPhone .$extension photos are not supported yet — '
          'convert to JPEG first.',
        );
      }
      throw MediaValidationException(
        "That file type can't be sent as ${_label(messageType)}.",
      );
    }
    final size = await file.length();
    final max = maxSizeBytes(messageType);
    if (size > max) {
      throw MediaValidationException(
        'That ${_label(messageType)} is too large '
        '(max ${max ~/ (1024 * 1024)} MB).',
      );
    }
  }
}
