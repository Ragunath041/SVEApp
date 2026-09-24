import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Animated background with floating orbs and subtle gradient
class AnimatedBackground extends StatefulWidget {
  final Widget child;
  final bool darkMode;

  const AnimatedBackground({
    super.key,
    required this.child,
    this.darkMode = false,
  });

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with TickerProviderStateMixin {
  late AnimationController _orbController;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _orbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base gradient
        Container(
          decoration: BoxDecoration(
            gradient: widget.darkMode
                ? AppColors.darkGradient
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.bgLight,
                      Color(0xFFEEF0FF),
                      AppColors.bgLight,
                    ],
                  ),
          ),
        ),

        // Floating orbs
        AnimatedBuilder(
          animation: _orbController,
          builder: (context, _) {
            return CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _OrbPainter(
                progress: _orbController.value,
                isDark: widget.darkMode,
              ),
            );
          },
        ),

        // Content
        widget.child,
      ],
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  _OrbPainter({required this.progress, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Orb 1 - Top right
    final orb1X = size.width * 0.8 + sin(progress * pi * 2) * 30;
    final orb1Y = size.height * 0.15 + cos(progress * pi * 2) * 20;
    paint.shader = RadialGradient(
      colors: [
        (isDark ? AppColors.primary : AppColors.primarySoft).withValues(
          alpha: 0.4,
        ),
        (isDark ? AppColors.primary : AppColors.primarySoft).withValues(
          alpha: 0.0,
        ),
      ],
    ).createShader(Rect.fromCircle(center: Offset(orb1X, orb1Y), radius: 120));
    canvas.drawCircle(Offset(orb1X, orb1Y), 120, paint);

    // Orb 2 - Bottom left
    final orb2X = size.width * 0.2 + cos(progress * pi * 2) * 25;
    final orb2Y = size.height * 0.7 + sin(progress * pi * 2) * 30;
    paint.shader = RadialGradient(
      colors: [
        (isDark ? AppColors.accent : AppColors.accentSoft).withValues(
          alpha: 0.3,
        ),
        (isDark ? AppColors.accent : AppColors.accentSoft).withValues(
          alpha: 0.0,
        ),
      ],
    ).createShader(Rect.fromCircle(center: Offset(orb2X, orb2Y), radius: 100));
    canvas.drawCircle(Offset(orb2X, orb2Y), 100, paint);

    // Orb 3 - Center
    final orb3X = size.width * 0.5 + sin(progress * pi * 1.5) * 20;
    final orb3Y = size.height * 0.4 + cos(progress * pi * 1.5) * 25;
    paint.shader = RadialGradient(
      colors: [
        (isDark ? AppColors.primaryLight : AppColors.primarySoft).withValues(
          alpha: 0.2,
        ),
        (isDark ? AppColors.primaryLight : AppColors.primarySoft).withValues(
          alpha: 0.0,
        ),
      ],
    ).createShader(Rect.fromCircle(center: Offset(orb3X, orb3Y), radius: 80));
    canvas.drawCircle(Offset(orb3X, orb3Y), 80, paint);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
