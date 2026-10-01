import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// Shared message composer. Extracted from the previously duplicated
/// input bars in `chat_screen.dart` and `group_chat_screen.dart`.
///
/// Visuals come from the theme; behavior (typing status, send) is owned
/// by the caller so 1:1 and group chats can differ.
class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttach;
  final ValueChanged<String>? onChanged;
  final String hintText;

  /// Optional strip rendered above the text row (e.g. the reply-to preview).
  /// Lives inside the decorated container so the top border stays put.
  final Widget? header;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.onAttach,
    this.onChanged,
    this.hintText = 'Type a message...',
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (header != null) ...[
                header!,
                const SizedBox(height: AppSpacing.xs),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (onAttach != null)
                    IconButton(
                      icon: const Icon(Icons.attach_file),
                      onPressed: onAttach,
                      tooltip: 'Attach',
                    ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(hintText: hintText),
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onChanged: onChanged,
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: onSend,
                    icon: const Icon(Icons.send, size: 20),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
