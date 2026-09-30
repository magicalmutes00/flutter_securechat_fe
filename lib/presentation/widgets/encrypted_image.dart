import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/message_model.dart';
import '../../data/services/api_client.dart';
import '../../data/services/e2ee/e2ee_service.dart';
import '../../data/services/media_cache_service.dart';

/// Displays an image attachment, downloading the (possibly encrypted) blob with
/// the authenticated API client and decrypting it in memory before rendering.
///
/// The AES key/nonce come from the decrypted Signal envelope held in
/// [Message.mediaKey]/[Message.mediaNonce]; they never touch disk. The
/// *decrypted* image is cached via [MediaCacheService] (encrypted at rest)
/// keyed by the attachment path, so re-opening a conversation — or viewing
/// media offline — does not re-download it.
class EncryptedImage extends StatefulWidget {
  const EncryptedImage({super.key, required this.message});

  final Message message;

  @override
  State<EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends State<EncryptedImage> {
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
  void didUpdateWidget(EncryptedImage oldWidget) {
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
      Uint8List decoded = Uint8List.fromList(raw);
      if (widget.message.mediaKey != null &&
          widget.message.mediaNonce != null) {
        decoded =
            await E2eeService.instance.decryptMediaBytes(widget.message, raw);
      }
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
        color: Colors.grey[300],
        child: const Center(
          child:
              Icon(Icons.lock_outline, size: 40, color: AppTheme.primaryColor),
        ),
      );
    }
    if (_bytes == null) {
      return Container(
        height: 200,
        width: 200,
        color: Colors.grey[300],
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
          color: Colors.grey[300],
          child: const Icon(Icons.broken_image, size: 50),
        ),
      ),
    );
  }
}
