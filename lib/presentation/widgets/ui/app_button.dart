import 'package:flutter/material.dart';

/// Button variants mapped to themed Material buttons.
enum AppButtonVariant { primary, secondary, ghost, danger }

/// Standardized button with built-in loading state.
///
/// Replaces the copy-pasted spinner-in-ElevatedButton blocks.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool loading;
  final bool expanded;
  final IconData? icon;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.expanded = true,
    this.icon,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.expanded = true,
    this.icon,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.expanded = true,
    this.icon,
  }) : variant = AppButtonVariant.ghost;

  const AppButton.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.expanded = true,
    this.icon,
  }) : variant = AppButtonVariant.danger;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final effectiveOnPressed = loading ? null : onPressed;

    Widget child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: variant == AppButtonVariant.ghost ||
                      variant == AppButtonVariant.secondary
                  ? colors.primary
                  : colors.onPrimary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label)),
            ],
          );

    Widget button;
    switch (variant) {
      case AppButtonVariant.primary:
        button = ElevatedButton(
          onPressed: effectiveOnPressed,
          child: child,
        );
      case AppButtonVariant.secondary:
        button = OutlinedButton(
          onPressed: effectiveOnPressed,
          child: child,
        );
      case AppButtonVariant.ghost:
        button = TextButton(
          onPressed: effectiveOnPressed,
          child: child,
        );
      case AppButtonVariant.danger:
        button = ElevatedButton(
          onPressed: effectiveOnPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          child: child,
        );
    }

    if (expanded) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
