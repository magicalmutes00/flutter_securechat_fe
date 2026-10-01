import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_tokens.dart';

/// WhatsApp-style swipe-to-reply wrapper for a chat bubble.
///
/// Dragging the bubble horizontally past the trigger distance calls [onReply]
/// (with haptic confirmation) and springs the bubble back. Only a horizontal
/// drag recognizer is registered, so the parent vertical [ListView] scroll
/// and the bubble's own tap/long-press gestures are unaffected.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const double _maxDrag = 96;
  static const double _triggerDx = 64;

  late final AnimationController _snapController;
  double _dx = 0;
  double _snapFrom = 0;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      duration: AppDurations.fast,
      vsync: this,
    );
    // Single permanent listener: no listener accumulation across drags, and
    // a new drag's stop() cleanly hands control back to the finger.
    _snapController.addListener(() {
      if (!mounted) return;
      setState(() {
        _dx = _snapFrom * (1 - Curves.easeOut.transform(_snapController.value));
      });
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    _snapController.stop();
    setState(() {
      _dx = (_dx + details.delta.dx).clamp(-_maxDrag, _maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled || _dx == 0) return;
    if (_dx.abs() >= _triggerDx) {
      HapticFeedback.selectionClick();
      widget.onReply();
    }
    _snapFrom = _dx;
    _snapController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dx.abs() / _triggerDx).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        children: [
          // Reply arrow revealed on the side the bubble moves away from.
          Positioned.fill(
            child: Opacity(
              opacity: progress,
              child: Align(
                alignment:
                    _dx >= 0 ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.reply,
                    size: 20,
                    color: context.appColors.primaryEmphasis,
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
