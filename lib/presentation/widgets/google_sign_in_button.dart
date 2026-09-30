import 'package:flutter/material.dart';

/// Branded "Sign in with Google" button following Google's identity
/// guidelines: white pill, the official four-color G, grey label.
///
/// The G is painted from the official 48x48 vector geometry (transcribed to
/// [Path] calls), so no image asset or SVG package is needed.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: isLoading ? null : onPressed,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFDADCE0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const _GoogleLogo(size: 20),
              const SizedBox(width: 12),
              const Text(
                'Sign in with Google',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF3C4043),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

/// The four segments of the official "G" mark in a 48x48 box, top-left to
/// bottom-right: red, blue, yellow, green.
class _GoogleLogoPainter extends CustomPainter {
  static const Color _red = Color(0xFFEA4335);
  static const Color _blue = Color(0xFF4285F4);
  static const Color _yellow = Color(0xFFFBBC05);
  static const Color _green = Color(0xFF34A853);

  static Path _redPath(Path p) => p
    ..moveTo(24, 9.5)
    ..relativeCubicTo(3.54, 0, 6.71, 1.22, 9.21, 3.6)
    ..relativeLineTo(6.85, -6.85)
    ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
    ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
    ..relativeLineTo(7.98, 6.19)
    ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
    ..close();

  static Path _bluePath(Path p) => p
    ..moveTo(46.98, 24.55)
    ..relativeCubicTo(0, -1.57, -0.15, -3.09, -0.38, -4.55)
    ..lineTo(24, 20)
    ..relativeLineTo(0, 9.02)
    ..relativeLineTo(12.94, 0)
    ..relativeCubicTo(-0.58, 2.96, -2.26, 5.48, -4.78, 7.18)
    ..relativeLineTo(7.73, 6)
    ..relativeCubicTo(4.51, -4.18, 7.09, -10.36, 7.09, -17.65)
    ..close();

  static Path _yellowPath(Path p) => p
    ..moveTo(10.53, 28.59)
    ..relativeCubicTo(-0.48, -1.45, -0.76, -2.99, -0.76, -4.59)
    // 's' (smooth cubic) expanded: reflected control point (9.77, 22.4).
    ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
    ..relativeLineTo(-7.98, -6.19)
    ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
    ..relativeCubicTo(0, 3.88, 0.92, 7.54, 2.56, 10.78)
    ..relativeLineTo(7.97, -6.19)
    ..close();

  static Path _greenPath(Path p) => p
    ..moveTo(24, 48)
    ..relativeCubicTo(6.48, 0, 11.93, -2.13, 15.89, -5.81)
    ..relativeLineTo(-7.73, -6)
    ..relativeCubicTo(-2.15, 1.45, -4.92, 2.3, -8.16, 2.3)
    ..relativeCubicTo(-6.26, 0, -11.57, -4.22, -13.47, -9.91)
    ..relativeLineTo(-7.98, 6.19)
    ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 48;
    canvas
      ..translate(
        (size.width - 48 * scale) / 2,
        (size.height - 48 * scale) / 2,
      )
      ..scale(scale);

    final segments = <(Color, Path Function(Path))>[
      (_red, _redPath),
      (_blue, _bluePath),
      (_yellow, _yellowPath),
      (_green, _greenPath),
    ];
    for (final (color, buildPath) in segments) {
      canvas.drawPath(buildPath(Path()), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
