import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/time_format.dart';
import '../../data/models/message_model.dart';
import 'encrypted_image.dart';
import 'ui/ui.dart';

/// Chat bubble. Sent messages are solid brand blue with white copy;
/// received messages are surface-toned. Read receipts use the lime accent.
class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onDelete,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppDurations.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _showActionsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SheetScaffold(
        title: 'Message',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isMe && widget.onDelete != null)
              ListTile(
                leading:
                    Icon(Icons.delete_outline, color: context.colors.error),
                title: const Text('Delete message'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete?.call();
                },
              ),
            if (widget.message.isTextMessage)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy text'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(
                      ClipboardData(text: widget.message.content));
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final bubbleColor =
        widget.isMe ? appColors.sentBubble : appColors.receivedBubble;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: _showActionsSheet,
        child: Align(
          alignment:
              widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: LayoutBuilder(
            builder: (context, constraints) => Container(
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.78,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppRadius.lg),
                  topRight: const Radius.circular(AppRadius.lg),
                  bottomLeft: widget.isMe
                      ? const Radius.circular(AppRadius.lg)
                      : Radius.zero,
                  bottomRight: widget.isMe
                      ? Radius.zero
                      : const Radius.circular(AppRadius.lg),
                ),
                boxShadow: AppShadows.card(Theme.of(context).brightness),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMessageContent(),
                  const SizedBox(height: AppSpacing.xs),
                  _buildMessageInfo(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _contentColor() {
    final appColors = context.appColors;
    return widget.isMe ? appColors.onSentBubble : appColors.onReceivedBubble;
  }

  Color _accentOnBubble() {
    // Icons inside a sent bubble sit on blue, so they use the bubble's own
    // foreground; inside a received bubble they use the theme emphasis.
    if (widget.isMe) return context.appColors.onSentBubble;
    return context.appColors.primaryEmphasis;
  }

  Widget _buildMessageContent() {
    final contentColor = _contentColor();
    if (widget.message.isTextMessage) {
      return Text(
        widget.message.content,
        style: context.text.bodyLarge?.copyWith(color: contentColor),
      );
    } else if (widget.message.isImageMessage) {
      return EncryptedImage(message: widget.message);
    } else if (widget.message.isVideoMessage) {
      return Container(
        height: 150,
        width: 200,
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Center(
          child: Icon(Icons.play_circle_fill,
              size: 50, color: _accentOnBubble()),
        ),
      );
    } else if (widget.message.isAudioMessage) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.audiotrack, color: _accentOnBubble()),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              widget.message.fileName ?? 'Audio',
              style: context.text.bodyMedium?.copyWith(
                color: contentColor,
                decoration: TextDecoration.underline,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else if (widget.message.isDocumentMessage) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, color: _accentOnBubble()),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.message.fileName ?? 'Document',
                  style: context.text.bodyMedium?.copyWith(
                    color: contentColor,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.message.fileSize != null)
                  Text(
                    _formatFileSize(widget.message.fileSize!),
                    style: context.text.bodySmall?.copyWith(
                      color: contentColor.withValues(alpha: 0.75),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildMessageInfo() {
    final infoColor = widget.isMe
        ? context.appColors.onSentBubble.withValues(alpha: 0.8)
        : context.colors.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatChatTime(widget.message.createdAt),
          style: context.text.labelSmall?.copyWith(color: infoColor),
        ),
        if (widget.isMe) ...[
          const SizedBox(width: AppSpacing.xs),
          _buildStatusIcon(),
        ],
      ],
    );
  }

  Widget _buildStatusIcon() {
    // Read receipts pop in lime on the blue bubble; delivery states stay
    // quiet so "read" is unmistakable.
    if (widget.message.isRead) {
      return const Icon(
        Icons.done_all,
        size: 15,
        color: AppPalette.lime400,
      );
    } else if (widget.message.isDelivered) {
      return Icon(
        Icons.done_all,
        size: 15,
        color:
            context.appColors.onSentBubble.withValues(alpha: 0.8),
      );
    } else {
      return Icon(
        Icons.done,
        size: 15,
        color:
            context.appColors.onSentBubble.withValues(alpha: 0.8),
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
