import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// Standard bottom-sheet body: title row + content with safe-area padding.
/// (The drag handle itself comes from the theme's `showDragHandle`.)
class SheetScaffold extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;

  const SheetScaffold({
    super.key,
    this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title!, style: context.text.titleLarge),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}
