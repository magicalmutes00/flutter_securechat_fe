import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/models/message_model.dart';
import '../../data/services/api_client.dart';
import '../../data/services/media_cache_service.dart';

/// Displays an image attachment in plaintext, downloading the bytes with the
/// authenticated API client and rendering them from memory.
///
/// The downloaded bytes are cached via [MediaCacheService] (encrypted at rest
/// for local storage protection) keyed by the attachment path, so re-opening
/// a conversation — or viewing media offline — does not re-download it.
class AttachmentImage extends StatefulWidget {
  const AttachmentImage({super.key, required this.message});

  final Message message;

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  final ApiClient _api = ApiClient();
  final MediaCacheService _cache = MediaCacheService();
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.filePath != widget.message.filePath) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  /// Optimistic temp bubbles reference the sender's on-device file rather
  /// than a hosted path — render those bytes directly instead of downloading.
  bool _isLocalPath(String path) =>
      !(path.startsWith('/api/') || path.startsWith('http'));

  Future<void> _load() async {
    final path = widget.message.filePath;
    if (path == null || path.isEmpty) {
      if (!mounted) return;
      setState(() => _failed = true);
      return;
    }

    if (_isLocalPath(path)) {
      try {
        final bytes = await File(path).readAsBytes();
        if (!mounted) return;
        setState(() => _bytes = bytes);
      } catch (_) {
        if (!mounted) return;
        setState(() => _failed = true);
      }
      return;
    }

    final cached = await _cache.read(path);
    if (cached != null) {
      if (!mounted) return;
      setState(() => _bytes = cached);
      return;
    }

    try {
      final url = path.startsWith('http') ? path : '${AppConstants.baseUrl}$path';
      final raw = await _api.downloadFileBytes(url);
      final bytes = Uint8List.fromList(raw);
      if (bytes.isEmpty) throw Exception('Empty media response');
      await _cache.write(path, bytes);
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        height: 200,
        width: 200,
        color: context.colors.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.broken_image,
              size: 40, color: context.colors.onSurfaceVariant),
        ),
      );
    }
    if (_bytes == null) {
      return Container(
        height: 200,
        width: 200,
        color: context.colors.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        _bytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Container(
          height: 200,
          width: 200,
          color: context.colors.surfaceContainerHighest,
          child: Icon(Icons.broken_image,
              size: 50, color: context.colors.onSurfaceVariant),
        ),
      ),
    );
  }
}
