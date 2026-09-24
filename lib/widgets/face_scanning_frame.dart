import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class FaceScanningFrame extends StatefulWidget {
  final double width;
  final double height;
  final bool isScanning;
  final Color? color;

  const FaceScanningFrame({
    super.key,
    this.width = 200,
    this.height = 260,
    this.isScanning = true,
    this.color,
  });

  @override
  State<FaceScanningFrame> createState() => _FaceScanningFrameState();
}

class _FaceScanningFrameState extends State<FaceScanningFrame>
    with TickerProviderStateMixin {
  late AnimationController _scanController;
  late AnimationController _pulseController;
  late Animation<double> _scanAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isScanning) {
      _scanController.repeat(reverse: true);
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.color ?? AppColors.accent;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulsing background glow
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, _) {
            return Container(
              width: widget.width + 20,
              height: widget.height + 20,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: activeColor.withValues(
                      alpha: 0.15 * _pulseAnimation.value,
                    ),
                    blurRadius: 40 * _pulseAnimation.value,
                    spreadRadius: 5 * _pulseAnimation.value,
                  ),
                ],
              ),
            );
          },
        ),

        // Main Frame
        Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            border: Border.all(
              color: activeColor.withValues(alpha: 0.2),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Stack(
            children: [
              // Corner brackets
              _buildCorner(Alignment.topLeft, activeColor),
              _buildCorner(Alignment.topRight, activeColor),
              _buildCorner(Alignment.bottomLeft, activeColor),
              _buildCorner(Alignment.bottomRight, activeColor),

              // Scanning line
              if (widget.isScanning)
                AnimatedBuilder(
                  animation: _scanAnimation,
                  builder: (context, child) {
                    return Positioned(
                      top: _scanAnimation.value * (widget.height - 2),
                      left: 10,
                      right: 10,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              activeColor.withValues(alpha: 0.0),
                              activeColor,
                              activeColor.withValues(alpha: 0.0),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 1,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCorner(Alignment alignment, Color color) {
    const double size = 24.0;
    const double thickness = 3.0;
    const double radius = 12.0;

    BorderRadius borderRadius;
    if (alignment == Alignment.topLeft) {
      borderRadius = const BorderRadius.only(topLeft: Radius.circular(radius));
    } else if (alignment == Alignment.topRight) {
      borderRadius = const BorderRadius.only(topRight: Radius.circular(radius));
    } else if (alignment == Alignment.bottomLeft) {
      borderRadius =
          const BorderRadius.only(bottomLeft: Radius.circular(radius));
    } else {
      borderRadius =
          const BorderRadius.only(bottomRight: Radius.circular(radius));
    }

    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border(
            top: (alignment == Alignment.topLeft ||
                    alignment == Alignment.topRight)
                ? BorderSide(color: color, width: thickness)
                : BorderSide.none,
            bottom: (alignment == Alignment.bottomLeft ||
                    alignment == Alignment.bottomRight)
                ? BorderSide(color: color, width: thickness)
                : BorderSide.none,
            left: (alignment == Alignment.topLeft ||
                    alignment == Alignment.bottomLeft)
                ? BorderSide(color: color, width: thickness)
                : BorderSide.none,
            right: (alignment == Alignment.topRight ||
                    alignment == Alignment.bottomRight)
                ? BorderSide(color: color, width: thickness)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
