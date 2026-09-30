import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/api_client.dart';
import '../../data/services/media_cache_service.dart';

/// Displays an image served by the authenticated file API
/// (`/api/files/<id>` — relative paths are prefixed with the server base URL).
///
/// `Image.network` cannot be used for these: the route requires a Bearer
/// token and answers with a redirect to a signed Cloudinary URL. This widget
/// downloads through [ApiClient] (which attaches the token), caches the
/// decrypted bytes via [MediaCacheService], and renders from memory.
class AuthImage extends StatefulWidget {
  const AuthImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorIcon = Icons.broken_image,
  });

  /// Relative file route (`/api/files/...`) or an absolute URL.
  final String path;
  final double? width;
  final double? height;
  final BoxFit? fit;

  /// Shown while loading; defaults to a spinner.
  final Widget? placeholder;
  final IconData errorIcon;

  @override
  State<AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<AuthImage> {
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
  void didUpdateWidget(AuthImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  String get _resolvedUrl => widget.path.startsWith('http')
      ? widget.path
      : '${AppConstants.baseUrl}${widget.path}';

  Future<void> _load() async {
    final key = widget.path;

    final cached = await _cache.read(key);
    if (cached != null) {
      if (!mounted) return;
      setState(() => _bytes = cached);
      return;
    }

    try {
      final raw = await _api.downloadFileBytes(_resolvedUrl);
      final bytes = Uint8List.fromList(raw);
      if (bytes.isEmpty) throw Exception('Empty media response');
      await _cache.write(key, bytes);
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
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Icon(widget.errorIcon, color: AppTheme.primaryColor),
      );
    }

    final bytes = _bytes;
    if (bytes == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.placeholder ??
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Image.memory(
      bytes,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(
        width: widget.width,
        height: widget.height,
        child: Icon(widget.errorIcon, color: AppTheme.primaryColor),
      ),
    );
  }
}
