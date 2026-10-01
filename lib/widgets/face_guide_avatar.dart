// ignore_for_file: deprecated_member_use

import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Animated face guide that shows the student which angle to pose
class FaceGuideAvatar extends StatefulWidget {
  final int currentStep; // 0-6 for 7 angles
  final double width;
  final double height;

  const FaceGuideAvatar({
    super.key,
    required this.currentStep,
    this.width = 220,
    this.height = 280,
  });

  @override
  State<FaceGuideAvatar> createState() => _FaceGuideAvatarState();
}

class _FaceGuideAvatarState extends State<FaceGuideAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // Returns rotation angles (yaw, pitch) for each step
  List<double> get _rotation {
    switch (widget.currentStep) {
      case 0:
        return [0.0, 0.0]; // Straight
      case 1:
        return [-0.3, 0.0]; // Slight Left
      case 2:
        return [0.3, 0.0]; // Slight Right
      case 3:
        return [-0.6, 0.0]; // Full Left
      case 4:
        return [0.6, 0.0]; // Full Right
      case 5:
        return [0.0, -0.3]; // Look Up
      case 6:
        return [0.0, 0.3]; // Look Down
      case 7:
        return [0.0, 0.0]; // Too Far
      case 8:
        return [0.0, 0.0]; // Too Close
      case 9:
        return [0.0, 0.0]; // Poor Light
      case 10:
        return [0.0, 0.0]; // Perfect
      default:
        return [0.0, 0.0];
    }
  }

  @override
  Widget build(BuildContext context) {
    final yaw = _rotation[0];
    final pitch = _rotation[1];

    // Calculate additional scale and colors based on tutorial states
    double tutorialScale = () {
      switch (widget.currentStep) {
        case 7:
          return 1.0; // Too Far - Make it very small
        case 8:
          return 2.2; // Too Close - High zoom pushes ears out of frame
        case 9:
          return 1.0; // Poor Light - Standard size
        case 10:
          return 1.0; // Perfect - Ideal size
        default:
          return 1.0;
      }
    }();

    Color baseColor = AppColors.primary;
    List<Color> gradientColors = [AppColors.primarySoft, AppColors.accentSoft];

    if (widget.currentStep == 7) {
      // Colors already set
    } else if (widget.currentStep == 8) {
      baseColor = Colors.red.withValues(alpha: 0.8);
      gradientColors = [Colors.transparent, Colors.transparent];
    } else if (widget.currentStep == 9) {
      baseColor = Colors.red; // Poor Light (Matches your logic)
      gradientColors = [Colors.grey[300]!, Colors.grey[400]!];
    } else if (widget.currentStep == 10) {
      baseColor = Colors.green; // Perfect
      gradientColors = [Colors.green[300]!, Colors.green[400]!];
    }

    final isTooClose = widget.currentStep == 8;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.width,
          height: widget.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final pulseAmount = isTooClose ? 0.15 : 0.05;
                final pulse = 1.0 + (_pulseController.value * pulseAmount);
                return Transform.scale(
                  scale: pulse * tutorialScale,
                  child: child,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOutCubic,
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: isTooClose
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradientColors,
                        ),
                  border: isTooClose
                      ? null
                      : Border.all(
                          color: baseColor.withValues(alpha: 0.3),
                          width: 2,
                        ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: Transform(
                    key: ValueKey(
                      widget.currentStep,
                    ), // Added key for AnimatedSwitcher
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001) // perspective
                      ..rotateY(yaw * 0.3)
                      ..rotateX(-pitch * 0.3)
                      ..translate(yaw * 10, pitch * 10),
                    alignment: Alignment.center,
                    child: ColorFiltered(
                      colorFilter: widget.currentStep == 9
                          ? ColorFilter.mode(
                              Colors.black.withValues(alpha: 0.6),
                              BlendMode.darken,
                            )
                          : const ColorFilter.mode(
                              Colors.transparent,
                              BlendMode.dst,
                            ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.asset(
                          () {
                            switch (widget.currentStep) {
                              case 7:
                                return 'assets/images/fullperson.png';
                              case 8:
                              case 9:
                              case 10:
                                return 'assets/images/image.png';
                              default:
                                return 'assets/images/image.png';
                            }
                          }(),
                          width: widget.width,
                          height: widget.height,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return CustomPaint(
                              size: Size(widget.width, widget.height),
                              painter: _FaceAvatarPainter(
                                yaw: yaw,
                                pitch: pitch,
                                color: baseColor,
                              ),
                            );
                          },
                        ), // Image
                      ), // ClipRRect
                    ), // ColorFiltered
                  ), // Transform
                ), // AnimatedSwitcher
              ), // AnimatedContainer
            ), // AnimatedBuilder
          ), // ClipRRect
        ), // SizedBox
        if (yaw != 0 || pitch != 0)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: CustomPaint(
              size: const Size(40, 40),
              painter: _DirectionArrowPainter(
                yaw: yaw,
                pitch: pitch,
                color: baseColor == AppColors.primary
                    ? const Color(0xFF00D4FF)
                    : baseColor,
              ),
            ),
          ),
      ],
    );
  }
}

/// Custom painter that draws a realistic human face for guidance
class _FaceAvatarPainter extends CustomPainter {
  final double yaw; // -1 to 1, left to right
  final double pitch; // -1 to 1, up to down
  final Color color;

  _FaceAvatarPainter({
    required this.yaw,
    required this.pitch,
    this.color = AppColors.primary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Adjust features based on yaw and pitch
    final double lookX = yaw * 15;
    final double lookY = pitch * 15;

    // ── Face Shape (Skin) ───────────────────
    final skinColor = const Color(0xFFFFD1AA);
    final skinShadow = const Color(0xFFE0B894);

    final facePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.3),
        colors: [skinColor.withValues(alpha: 1.0), skinShadow],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final facePath = Path()
      ..addOval(
        Rect.fromCenter(
          center: center,
          width: radius * 1.6,
          height: radius * 2.0,
        ),
      );
    canvas.drawPath(facePath, facePaint);

    // ── Ears ───────────────────
    final earPaint = Paint()..color = skinShadow;
    final leftEarX = center.dx - radius * 0.8 + (yaw * 5);
    final rightEarX = center.dx + radius * 0.8 + (yaw * 5);
    final earY = center.dy + (pitch * 5);

    // Draw only if visible based on yaw
    if (yaw < 0.8) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(leftEarX, earY), width: 12, height: 26),
        earPaint,
      );
    }
    if (yaw > -0.8) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(rightEarX, earY), width: 12, height: 26),
        earPaint,
      );
    }

    // ── Hair ───────────────────
    final hairPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF3E2723), Colors.black],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final hairPath = Path()
      ..moveTo(center.dx - radius * 0.85, center.dy - radius * 0.2)
      ..quadraticBezierTo(
        center.dx - radius * 0.8,
        center.dy - radius * 1.1,
        center.dx,
        center.dy - radius * 1.15,
      )
      ..quadraticBezierTo(
        center.dx + radius * 0.8,
        center.dy - radius * 1.1,
        center.dx + radius * 0.85,
        center.dy - radius * 0.2,
      )
      ..quadraticBezierTo(
        center.dx + radius * 0.5,
        center.dy - radius * 0.7,
        center.dx,
        center.dy - radius * 0.6,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.5,
        center.dy - radius * 0.7,
        center.dx - radius * 0.85,
        center.dy - radius * 0.2,
      )
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    // ── Features Container (Dynamic Movement) ───────────
    canvas.save();
    canvas.translate(lookX, lookY);

    // ── Eyebrows ───────────────────
    final browPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final lbrow = Path()
      ..moveTo(center.dx - 45, center.dy - 35)
      ..quadraticBezierTo(
        center.dx - 30,
        center.dy - 42,
        center.dx - 15,
        center.dy - 35,
      );
    final rbrow = Path()
      ..moveTo(center.dx + 15, center.dy - 35)
      ..quadraticBezierTo(
        center.dx + 30,
        center.dy - 42,
        center.dx + 45,
        center.dy - 35,
      );

    canvas.drawPath(lbrow, browPaint);
    canvas.drawPath(rbrow, browPaint);

    // ── Eyes (Detailed) ───────────────────
    final whitePaint = Paint()..color = Colors.white;
    final irisPaint = Paint()..color = const Color(0xFF3E2723);
    final pupilPaint = Paint()..color = Colors.black;

    void drawEye(Offset pos) {
      canvas.drawOval(
        Rect.fromCenter(center: pos, width: 22, height: 12),
        whitePaint,
      );
      canvas.drawCircle(pos, 5, irisPaint);
      canvas.drawCircle(pos, 2, pupilPaint);
      // Reflection
      canvas.drawCircle(
        pos.translate(-2, -2),
        1,
        Paint()..color = Colors.white70,
      );
    }

    drawEye(Offset(center.dx - 30, center.dy - 20));
    drawEye(Offset(center.dx + 30, center.dy - 20));

    // ── Nose ───────────────────
    final nosePaint = Paint()
      ..color = skinShadow.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final nose = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx, center.dy + 15)
      ..quadraticBezierTo(
        center.dx - 6,
        center.dy + 20,
        center.dx,
        center.dy + 20,
      )
      ..quadraticBezierTo(
        center.dx + 6,
        center.dy + 20,
        center.dx,
        center.dy + 20,
      );
    canvas.drawPath(nose, nosePaint);

    // ── Lips ───────────────────
    final lipPaint = Paint()
      ..shader =
          LinearGradient(
            colors: [const Color(0xFFE57373), const Color(0xFFC62828)],
          ).createShader(
            Rect.fromCenter(
              center: Offset(center.dx, center.dy + 45),
              width: 40,
              height: 15,
            ),
          );

    final lips = Path()
      ..moveTo(center.dx - 20, center.dy + 45)
      ..quadraticBezierTo(
        center.dx,
        center.dy + 40,
        center.dx + 20,
        center.dy + 45,
      )
      ..quadraticBezierTo(
        center.dx,
        center.dy + 52,
        center.dx - 20,
        center.dy + 45,
      )
      ..close();
    canvas.drawPath(lips, lipPaint);

    canvas.restore();

    // ── Direction Arrow (High Tech) ───────────────────
    // Feature drawing removed since we use Image.asset
    // Keeping painter as fallback
  }

  @override
  bool shouldRepaint(covariant _FaceAvatarPainter oldDelegate) =>
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch ||
      oldDelegate.color != color;
}

/// Painter for high-tech guidance arrow
class _DirectionArrowPainter extends CustomPainter {
  final double yaw;
  final double pitch;
  final Color color;

  _DirectionArrowPainter({
    required this.yaw,
    required this.pitch,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // Scale the arrow length based on the smaller dimension of the canvas
    final double length =
        min(size.width, size.height) * 0.4; // Adjusted scaling factor
    final tipX = center.dx + yaw * length;
    final tipY = center.dy + pitch * length;

    final arrow = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(tipX, tipY);

    final double angle = atan2(pitch, yaw);
    const double tipSize = 12;
    arrow.moveTo(tipX, tipY);
    arrow.lineTo(
      tipX - tipSize * cos(angle - 0.4),
      tipY - tipSize * sin(angle - 0.4),
    );
    arrow.moveTo(tipX, tipY);
    arrow.lineTo(
      tipX - tipSize * cos(angle + 0.4),
      tipY - tipSize * sin(angle + 0.4),
    );

    canvas.drawPath(arrow, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _DirectionArrowPainter oldDelegate) =>
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch ||
      oldDelegate.color != color;
}
