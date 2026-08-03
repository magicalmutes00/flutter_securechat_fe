import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/status_model.dart';
import '../../data/models/user_model.dart';
import '../../data/services/api_client.dart';

/// Full-screen status viewer with per-story progress bars and auto-advance.
/// Tap the left/right half to go back/forward; long-press to pause.
class StoryViewerScreen extends StatefulWidget {
  final User user;
  final List<Status> statuses;
  final String currentUserId;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.user,
    required this.statuses,
    required this.currentUserId,
    this.initialIndex = 0,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  final ApiClient _api = ApiClient();
  int _currentIndex = 0;
  double _progress = 0;
  Timer? _timer;
  bool _paused = false;
  bool _dismissed = false;

  static const Duration _storyDuration = Duration(seconds: 5);
  static const int _ticks = 100;
  Duration get _tickDuration => _storyDuration ~/ _ticks;

  List<Status> get _statuses => widget.statuses;
  Status get _current => _statuses[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _start();
    _markViewed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _progress = 0;
    _timer?.cancel();
    _timer = Timer.periodic(_tickDuration, (t) {
      if (!mounted || _paused) return;
      setState(() => _progress += 1 / _ticks);
      if (_progress >= 1) {
        _next();
      }
    });
  }

  void _markViewed() {
    final status = _current;
    if (!status.hasBeenViewedBy(widget.currentUserId)) {
      _api.markStatusViewed(status.id).then((_) {}, onError: (Object e) {});
    }
  }

  void _next() {
    if (_currentIndex < _statuses.length - 1) {
      setState(() => _currentIndex++);
      _start();
      _markViewed();
    } else {
      _close();
    }
  }

  void _previous() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _start();
      _markViewed();
    }
  }

  void _close() {
    if (_dismissed) return;
    _dismissed = true;
    if (mounted) Navigator.of(context).pop();
  }

  void _handleTap(TapUpDetails details) {
    final width = MediaQuery.of(context).size.width;
    if (details.globalPosition.dx < width * 0.35) {
      _previous();
    } else {
      _next();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _handleTap,
          onLongPressStart: (_) => _paused = true,
          onLongPressEnd: (_) => _paused = false,
          child: Stack(
            children: [
              Positioned.fill(
                child: _buildStoryContent(_current),
              ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < _statuses.length; i++)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: i == _currentIndex
                                      ? _progress
                                      : (i < _currentIndex ? 1 : 0),
                                  minHeight: 3,
                                  backgroundColor: Colors.white24,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.white24,
                          child: _userInitial(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _userName(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 26),
                          onPressed: _close,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _userInitial() {
    final name = _userName();
    return name.isEmpty
        ? null
        : Text(
            name[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          );
  }

  String _userName() =>
      _statuses[_currentIndex].author?.displayName ??
      widget.user.displayName ??
      widget.user.email ??
      widget.user.phone ??
      '';

  Widget _buildStoryContent(Status status) {
    if (status.isImage) {
      return Image.network(
        '${AppConstants.baseUrl}${status.mediaPath}',
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          status.text ?? '',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
