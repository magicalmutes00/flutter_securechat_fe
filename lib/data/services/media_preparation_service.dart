import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';

/// Thrown when a picked file must not be uploaded. Carries the exact line
/// the UI shows — validation runs on-device before any upload work, so these
/// rejections are instant and free.
class MediaValidationException implements Exception {
  const MediaValidationException(this.message);

  final String message;

  @override
  String toString() => 'MediaValidationException: $message';
}

/// Pre-flight checks for outgoing attachments. Mirrors the server's
/// extension allow-list and the app's per-type size caps so doomed uploads
/// fail here — instantly — instead of after a full upload cycle.
class MediaPreparationService {
  MediaPreparationService._();

  /// Must stay in sync with the backend's `allowedFileExtensions`.
  /// HEIC/HEIF are absent on purpose — the server rejects them, so they fail
  /// here with an actionable message instead of a bare 400 after uploading
  /// megabytes.
  static const Map<String, List<String>> allowedExtensions = {
    AppConstants.messageTypeImage: [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
    ],
    AppConstants.messageTypeVideo: [
      'mp4',
      'mov',
      'avi',
      'mkv',
      'webm',
    ],
    AppConstants.messageTypeAudio: [
      'mp3',
      'wav',
      'aac',
      'm4a',
      'ogg',
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

  /// Photos 12 MP and up are the norm; uploading them raw means sending
  /// ~5-10x the bytes a chat bubble needs. Compress to a bounded JPEG
  /// before upload instead.
  static const int compressMaxDimension = 1600;
  static const int compressQuality = 80;

  /// Files at or below this size skip conversion — not worth the CPU, and
  /// re-encoding a tiny image can even grow it.
  static const int compressSkipBelowBytes = 1024 * 1024;

  /// Whether [prepareImage] would convert the file. Pure and unit-tested;
  /// the native conversion itself can't run in `flutter test`.
  static bool shouldCompress({
    required String extension,
    required int sizeBytes,
    required String messageType,
  }) {
    // Only still photos are resized; video/audio/documents upload as-is.
    if (messageType != AppConstants.messageTypeImage) return false;
    // GIF and WebP can animate — re-encoding to JPEG would silently kill
    // that, so they pass through untouched.
    if (extension == 'gif' || extension == 'webp') return false;
    // HEIC/HEIF are always attempted: a successful conversion is the only
    // way those photos become sendable at all (the server rejects the
    // format). A native-codec failure falls back to the original below.
    if (extension == 'heic' || extension == 'heif') return true;
    return sizeBytes > compressSkipBelowBytes;
  }

  /// Converts a picked photo to a bounded JPEG and returns the path to
  /// upload. Returns [filePath] unchanged when conversion is
  /// pointless (small/GIF/WebP/non-image) or the native codec fails.
  /// Throws [MediaValidationException] when the file is gone.
  static Future<String> prepareImage({
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
    final size = await file.length();
    if (!shouldCompress(
        extension: extension, sizeBytes: size, messageType: messageType)) {
      return filePath;
    }
    final tmp = await getTemporaryDirectory();
    final target =
        '${tmp.path}/sc_img_${DateTime.now().microsecondsSinceEpoch}.jpg';
    try {
      final out = await FlutterImageCompress.compressAndGetFile(
        filePath,
        target,
        minWidth: compressMaxDimension,
        minHeight: compressMaxDimension,
        quality: compressQuality,
      );
      if (out == null) return filePath;
      final outLen = await File(out.path).length();
      if (outLen >= size) {
        // No win (e.g. a tiny input the scaler grew): drop it, keep the
        // original.
        try {
          await File(out.path).delete();
        } catch (_) {}
        return filePath;
      }
      return out.path;
    } catch (_) {
      // Native codec missing (e.g. HEIC on some Android builds): fall back
      // to the original; validation rules on its acceptability.
      return filePath;
    }
  }

  /// Upload filename for a prepared file: passthrough normally, but a
  /// converted photo takes the original stem with a `.jpg` extension so the
  /// server's extension allow-list sees what the bytes actually are.
  static String uploadFilename(String originalPath, String sendPath) {
    final original = originalPath.split('/').last.split('\\').last;
    if (sendPath == originalPath) return original;
    final dot = original.lastIndexOf('.');
    final stem = dot == -1 ? original : original.substring(0, dot);
    return '$stem.jpg';
  }

  /// Deletes our own transient files (compressed copies). Never touches the
  /// original — it belongs to the picker/gallery.
  static Future<void> deleteTemp(String path, String originalPath) async {
    if (path == originalPath) return;
    try {
      await File(path).delete();
    } catch (_) {}
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
