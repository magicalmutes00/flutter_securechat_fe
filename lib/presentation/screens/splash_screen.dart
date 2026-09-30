import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Branded launch screen shown while auth state resolves.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo.png', width: 96, height: 96),
            const SizedBox(height: AppSpacing.lg),
            Text('SecureChat', style: context.text.headlineMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Private messaging, beautifully simple',
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
