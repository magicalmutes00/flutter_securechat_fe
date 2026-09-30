import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

/// Branded empty state: lime-tinted icon medallion, title, optional body
/// and call-to-action. Replaces the hand-rolled icon+text columns.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: colors.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title,
                textAlign: TextAlign.center, style: text.titleLarge),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: text.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Branded error state with retry.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Something went wrong',
      body: message,
      actionLabel: onRetry == null ? null : 'Retry',
      onAction: onRetry,
    );
  }
}

/// Self-pulsing skeleton block (no extra dependency).
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadius.sm,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.slow,
      lowerBound: 0.45,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Skeleton placeholder for a scrolling list of rows.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 64,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, _) => Row(
        children: [
          const SkeletonBox(width: 48, height: 48, radius: AppRadius.pill),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(
                    width: MediaQuery.of(context).size.width * 0.4, height: 14),
                const SizedBox(height: AppSpacing.sm),
                SkeletonBox(
                    width: MediaQuery.of(context).size.width * 0.6, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
