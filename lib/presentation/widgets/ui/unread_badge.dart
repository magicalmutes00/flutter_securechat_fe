import 'package:flutter/material.dart';

/// Lime unread-count pill (dark text on lime — the only legible way to use
/// the accent on light surfaces).
class UnreadBadge extends StatelessWidget {
  final int count;
  final bool showZero;

  const UnreadBadge({
    super.key,
    required this.count,
    this.showZero = false,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0 && !showZero) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onSecondary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
