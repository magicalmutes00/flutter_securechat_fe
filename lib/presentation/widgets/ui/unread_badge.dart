import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Compact unread-count badge (WhatsApp-style): circle for single digits,
/// wider pill for 10–99, `99+` beyond that. Sizing is content-driven —
/// the badge never expands to its parent's width.
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
    final label = count > 99 ? '99+' : '$count';
    // MainAxisSize.min keeps the badge content-sized even inside a
    // max-width parent (e.g. a Column): a bare Container would stretch to
    // the parent's full width and render as a bar.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: AppPalette.lime400,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101010),
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}
