import 'package:flutter/material.dart';
import 'dart:math';

class AnimatedSplashWidget extends StatefulWidget {
  final Duration duration;
  final VoidCallback? onComplete;

  const AnimatedSplashWidget({
    Key? key,
    this.duration = const Duration(milliseconds: 2500),
    this.onComplete,
  }) : super(key: key);

  @override
  State<AnimatedSplashWidget> createState() => _AnimatedSplashWidgetState();
}

class _AnimatedSplashWidgetState extends State<AnimatedSplashWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          color: Colors.white,
          child: CustomPaint(
            painter: SplashPainter(
              progress: _animation.value,
            ),
            child: Container(),
          ),
        );
      },
    );
  }
}

class SplashPainter extends CustomPainter {
  final double progress;
  static const int particleCount = 20;

  SplashPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2.5);
    final random = Random(42); // Fixed seed for consistency

    // Phase 1 (0.0 - 0.4): Break apart
    // Phase 2 (0.4 - 1.0): Reassemble
    double breakPhase = progress < 0.4 ? progress / 0.4 : 1.0;
    double reassemblePhase = progress > 0.4 ? (progress - 0.4) / 0.6 : 0.0;

    for (int i = 0; i < particleCount; i++) {
      final angle = (i / particleCount) * 2 * pi;
      final distance = 200 * breakPhase;

      // Particle position during break phase
      final breakX = center.dx + distance * cos(angle);
      final breakY = center.dy + distance * sin(angle);

      // Return to center during reassemble phase
      final finalX = center.dx + (breakX - center.dx) * (1 - reassemblePhase);
      final finalY = center.dy + (breakY - center.dy) * (1 - reassemblePhase);

      // Draw particle
      final paint = Paint()
        ..color = _getLogoColor(i).withOpacity(1.0 - reassemblePhase * 0.2)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(finalX, finalY),
        8,
        paint,
      );
    }

    // Draw reassembled logo (opacity increases as it reassembles)
    if (reassemblePhase > 0) {
      _drawLogo(canvas, center, reassemblePhase);
    }

    // Draw animated ball
    _drawAnimatedBall(canvas, size, center);
  }

  void _drawAnimatedBall(Canvas canvas, Size size, Offset logoCenter) {
    // Bounce effect
    final bouncePhase = (progress * 4) % 1.0;
    final bounceHeight = sin(bouncePhase * pi) * 30;

    final ballY = logoCenter.dy + 150 - bounceHeight;
    final ballX = size.width / 2;

    // Draw NESF Foundation logo (soccer ball)
    _drawFoundationLogo(canvas, Offset(ballX, ballY), 60);

    // Loading text
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Loading...',
        style: TextStyle(
          color: Color(0xFF1a237e),
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        size.width / 2 - textPainter.width / 2,
        ballY + 90,
      ),
    );
  }

  void _drawFoundationLogo(Canvas canvas, Offset center, double size) {
    // Draw soccer ball (pentagon pattern)
    final ballPaint = Paint()
      ..color = const Color(0xFFFFC107) // Brand yellow
      ..style = PaintingStyle.fill;

    // Outer circle (ball)
    canvas.drawCircle(center, size / 2, ballPaint);

    // Pentagon pattern on ball (5-sided pattern)
    final pentagonPaint = Paint()
      ..color = const Color(0xFF1a237e) // Brand blue
      ..style = PaintingStyle.fill;

    final polygonSize = size * 0.15;
    for (int i = 0; i < 5; i++) {
      final angle = (i / 5) * 2 * pi - pi / 2;
      final x = center.dx + (size * 0.25) * cos(angle);
      final y = center.dy + (size * 0.25) * sin(angle);

      canvas.drawCircle(Offset(x, y), polygonSize, pentagonPaint);
    }

    // Center pentagon
    canvas.drawCircle(center, polygonSize * 1.5, pentagonPaint);

    // Ball shine (top-left)
    final shinePaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(center.dx - size * 0.15, center.dy - size * 0.15),
      size * 0.12,
      shinePaint,
    );
  }

  void _drawLogo(Canvas canvas, Offset center, double opacity) {
    // Simple placeholder: draw the NE SPORTS text
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'NE SPORTS',
        style: TextStyle(
          color: Colors.black.withOpacity(opacity),
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  Color _getLogoColor(int index) {
    final colors = [
      Color(0xFF1a237e), // Blue
      Color(0xFFFFC107), // Yellow
      Color(0xFFFF6F00), // Orange
      Color(0xFF4CAF50), // Green
      Color(0xFFFFFFFF), // White
    ];
    return colors[index % colors.length];
  }

  @override
  bool shouldRepaint(SplashPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
