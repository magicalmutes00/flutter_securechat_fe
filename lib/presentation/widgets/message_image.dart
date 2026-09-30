import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/models/message_model.dart';
import '../../data/services/api_client.dart';
import '../../data/services/media_cache_service.dart';

/// Displays an image attachment, downloading the blob with the authenticated
/// API client and caching the bytes for instant re-viewing and offline use.
class MessageImage extends StatefulWidget {
  const MessageImage({super.key, required this.message});

  final Message message;

  @override
  State<MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends State<MessageImage> {
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
  void didUpdateWidget(MessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.message.filePath;
    if (path == null || path.isEmpty) {
      setState(() => _failed = true);
      return;
    }

    final cached = await _cache.read(path);
    if (cached != null) {
      if (!mounted) return;
      setState(() => _bytes = cached);
      return;
    }

    try {
      final raw = await _api.downloadFileBytes('${AppConstants.baseUrl}$path');
      final decoded = Uint8List.fromList(raw);
      await _cache.write(path, decoded);
      if (!mounted) return;
      setState(() => _bytes = decoded);
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
