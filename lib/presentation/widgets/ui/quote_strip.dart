import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../data/models/message_model.dart';

/// Colors for a [QuoteStrip], supplied by the caller so the same strip works
/// on a sent bubble (blue), a received bubble (surface), and the composer.
class QuoteStripStyle {
  final Color barColor;
  final Color nameColor;
  final Color snippetColor;
  final Color? backgroundColor;

  const QuoteStripStyle({
    required this.barColor,
    required this.nameColor,
    required this.snippetColor,
    this.backgroundColor,
  });
}

/// The quoted-message preview: accent bar + sender name + 2-line snippet,
/// shared by the in-bubble quote and the composer reply header.
class QuoteStrip extends StatelessWidget {
  final String senderName;
  final String snippet;
  final IconData? leadingIcon;
  final QuoteStripStyle style;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  const QuoteStrip({
    super.key,
    required this.senderName,
    required this.snippet,
    this.leadingIcon,
    required this.style,
    this.onTap,
    this.onClose,
  });

  /// Strip for a quote that cannot be resolved (message too old to be loaded,
  /// or deleted since). Never tappable — there is nowhere to jump to.
  factory QuoteStrip.unavailable({
    Key? key,
    required QuoteStripStyle style,
  }) {
    return QuoteStrip(
      key: key,
      senderName: 'Original message',
      snippet: 'Message unavailable',
      leadingIcon: Icons.block_outlined,
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strip = Container(
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: style.barColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderName,
                  style: context.text.labelMedium?.copyWith(
                    color: style.nameColor,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    if (leadingIcon != null) ...[
                      Icon(leadingIcon, size: 14, color: style.snippetColor),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Expanded(
                      child: Text(
                        snippet,
                        style: context.text.bodySmall?.copyWith(
                          color: style.snippetColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onClose != null)
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Icon(Icons.close, size: 18, color: style.snippetColor),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return strip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: strip,
    );
  }
}

/// One-line preview of a message for quote strips. Purely presentational —
/// resolved from an already-loaded [Message], never re-fetched.
class ReplySnippet {
  final String text;
  final IconData? icon;

  const ReplySnippet._(this.text, this.icon);

  factory ReplySnippet.forMessage(Message message) {
    if (message.isTextMessage) {
      final content = message.content.trim();
      return ReplySnippet._(
        content.isEmpty ? 'Message unavailable' : content,
        null,
      );
    }
    if (message.isImageMessage) {
      return const ReplySnippet._('Photo', Icons.image_outlined);
    }
    if (message.isVideoMessage) {
      return const ReplySnippet._('Video', Icons.videocam_outlined);
    }
    if (message.isAudioMessage) {
      return ReplySnippet._(
        message.fileName ?? 'Audio message',
        Icons.audiotrack_outlined,
      );
    }
    return ReplySnippet._(
      message.fileName ?? 'Document',
      Icons.insert_drive_file_outlined,
    );
  }
}
