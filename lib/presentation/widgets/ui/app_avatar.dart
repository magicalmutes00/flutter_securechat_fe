import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// Branded avatar: primary-tinted disc with initials fallback, optional
/// clipped image, and an optional lime presence dot.
class AppAvatar extends StatelessWidget {
  final String label;
  final double radius;
  final Widget? image;
  final bool? isOnline;
  final VoidCallback? onTap;

  const AppAvatar({
    super.key,
    required this.label,
    this.radius = 24,
    this.image,
    this.isOnline,
    this.onTap,
  });

  String get _initials {
    final parts =
        label.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final appColors = context.appColors;

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: colors.primaryContainer,
      foregroundColor: colors.onPrimaryContainer,
      child: image != null
          ? ClipOval(
              child: SizedBox(
                width: radius * 2,
                height: radius * 2,
                child: image,
              ),
            )
          : Text(
              _initials,
              style: context.text.titleMedium?.copyWith(
                color: colors.onPrimaryContainer,
                fontSize: radius * 0.7,
              ),
            ),
    );

    Widget result = avatar;
    if (isOnline != null) {
      final dotSize = (radius * 0.42).clamp(10.0, 16.0);
      result = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: isOnline!
                    ? appColors.presenceOnline
                    : appColors.presenceOffline,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surface, width: 2),
              ),
            ),
          ),
        ],
      );
    }

    if (onTap == null) return result;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: result,
    );
  }
}
