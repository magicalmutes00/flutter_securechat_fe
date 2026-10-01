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

  /// Already-decrypted quoted message, or null when the target isn't loaded
  /// (older than the fetched page, or deleted since). The bubble renders a
  /// strip whenever [Message.replyToId] is set, falling back to an
  /// "unavailable" strip when this is null.
  final Message? quotedMessage;

  /// Display name of the quoted message's sender.
  final String? quotedSenderName;

  /// Called on swipe-to-reply and from the "Reply" sheet row. Null disables
  /// both affordances.
  final VoidCallback? onReply;

  /// Called when the quote strip is tapped (scroll to the original).
  final VoidCallback? onTapQuote;

  /// Briefly true after a quote-strip jump lands here: renders a glow ring.
  final bool isHighlighted;

  /// Called when a failed own-bubble's error icon is tapped (re-run the
  /// send). Null hides the retry affordance even on failed bubbles.
  final VoidCallback? onRetry;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onDelete,
    this.onTap,
    this.onLongPress,
    this.quotedMessage,
    this.quotedSenderName,
    this.onReply,
    this.onTapQuote,
    this.isHighlighted = false,
    this.onRetry,
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
            if (widget.onReply != null)
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onReply?.call();
                },
              ),
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
      child: SwipeToReply(
        enabled: widget.onReply != null,
        onReply: () => widget.onReply?.call(),
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
                  border: widget.isHighlighted
                      ? Border.all(color: AppPalette.lime400, width: 2)
                      : null,
                  boxShadow: widget.isHighlighted
                      ? [
                          BoxShadow(
                            color: AppPalette.lime400.withValues(alpha: 0.45),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : AppShadows.card(Theme.of(context).brightness),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.message.replyToId != null) _buildQuoteStrip(),
                    _buildMessageContent(),
                    const SizedBox(height: AppSpacing.xs),
                    _buildMessageInfo(),
                  ],
                ),
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

  Widget _buildQuoteStrip() {
    final appColors = context.appColors;
    final style = widget.isMe
        ? QuoteStripStyle(
            barColor: appColors.onSentBubble,
            nameColor: appColors.onSentBubble,
            snippetColor: appColors.onSentBubble.withValues(alpha: 0.85),
            backgroundColor: appColors.onSentBubble.withValues(alpha: 0.14),
          )
        : QuoteStripStyle(
            barColor: appColors.primaryEmphasis,
            nameColor: appColors.primaryEmphasis,
            snippetColor: context.colors.onSurfaceVariant,
            backgroundColor:
                context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
          );
    final quoted = widget.quotedMessage;
    final Widget strip = quoted == null
        ? QuoteStrip.unavailable(style: style)
        : () {
            final snippet = ReplySnippet.forMessage(quoted);
            return QuoteStrip(
              senderName: widget.quotedSenderName ?? 'Unknown',
              snippet: snippet.text,
              leadingIcon: snippet.icon,
              style: style,
              onTap: widget.onTapQuote,
            );
          }();
    // Quotes span the bubble width like WhatsApp; the message body below
    // keeps its natural width.
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: SizedBox(width: double.infinity, child: strip),
    );
  }

  Widget _buildMessageContent() {
    final content = _buildContentBody();
    final progress = widget.message.uploadProgress;
    // In-flight uploads dim under a determinate ring; every media kind
    // shares this overlay so video/audio/documents need no special case.
    if (!widget.message.isSending || progress == null || progress >= 1) {
      return content;
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0.55, child: content),
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 3,
            backgroundColor:
                context.appColors.onSentBubble.withValues(alpha: 0.25),
            valueColor: AlwaysStoppedAnimation<Color>(
              widget.isMe
                  ? context.appColors.onSentBubble
                  : context.appColors.primaryEmphasis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContentBody() {
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
    // A failed send shows a tappable red icon (retry); an in-flight
    // optimistic send shows a quiet clock. Neither disturbs the thread.
    if (widget.message.isFailed) {
      final icon = Icon(
        Icons.error_outline,
        size: 16,
        color: context.colors.error,
      );
      if (widget.onRetry == null) return icon;
      return GestureDetector(
        onTap: widget.onRetry,
        behavior: HitTestBehavior.opaque,
        child: icon,
      );
    }
    if (widget.message.isSending) {
      return Icon(
        Icons.access_time,
        size: 15,
        color: context.appColors.onSentBubble.withValues(alpha: 0.8),
      );
    }
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
