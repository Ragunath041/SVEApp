import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/face_guide_avatar.dart';
import '../widgets/animated_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/face_scanning_frame.dart';

class FaceCaptureGuidePage extends StatefulWidget {
  final Widget nextPage;
  final String title;

  const FaceCaptureGuidePage({
    super.key,
    required this.nextPage,
    this.title = 'Face Capture Guide',
  });

  @override
  State<FaceCaptureGuidePage> createState() => _FaceCaptureGuidePageState();
}

class _FaceCaptureGuidePageState extends State<FaceCaptureGuidePage> {
  int _step = 7; // Start with "Too Far"
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _step = _step + 1;
          if (_step > 10) _step = 7;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String stepTitle = "WAITING";
    String stepDesc = "";
    Color stepColor = Colors.blue;

    switch (_step) {
      case 7:
        stepTitle = "TOO FAR";
        stepDesc = "Move closer to the camera so your face fits in the box.";
        stepColor = Colors.red;
        break;
      case 8:
        stepTitle = "TOO CLOSE";
        stepDesc = "Keep a stable distance from the camera.";
        stepColor = Colors.red;
        break;
      case 9:
        stepTitle = "POOR LIGHT";
        stepDesc = "Ensure your face is well lit and not in shadows.";
        stepColor = Colors.red;
        break;
      case 10:
        stepTitle = "PERFECT";
        stepDesc = "This is the ideal pose for registration and login.";
        stepColor = Colors.green;
        break;
    }

    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenH = constraints.maxHeight;
              // Scale avatar based on available height so it fits small phones
              final avatarH = (screenH * 0.33).clamp(140.0, 240.0);
              final avatarW = avatarH * (220 / 280);
              final topSpacing = screenH < 600 ? 8.0 : 16.0;
              final midSpacing = screenH < 600 ? 10.0 : 20.0;
              final cardVertPad = screenH < 600 ? 12.0 : 20.0;
              final innerSpacing = screenH < 600 ? 12.0 : 24.0;
              final titleFontSize = screenH < 600 ? 18.0 : 22.0;
              final btnSpacing = screenH < 600 ? 12.0 : 24.0;

              return Column(
                children: [
                  // ── Header ──────────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(14, topSpacing, 14, 0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: topSpacing),
                        Text(
                          "Face Capture Do's and Don'ts",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Follow these tips for a successful capture",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: midSpacing),

                  // ── Card (fills remaining space) ─────────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: GlassCard(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: cardVertPad),
                          child: ClipRect(
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      FaceScanningFrame(
                                        width: avatarW,
                                        height: avatarH,
                                        color: stepColor,
                                        isScanning: _step == 10,
                                      ),
                                      FaceGuideAvatar(
                                        currentStep: _step,
                                        width: avatarW,
                                        height: avatarH,
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: innerSpacing),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: Column(
                                      key: ValueKey(_step),
                                      children: [
                                        Text(
                                          stepTitle,
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            color: stepColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                          ),
                                          child: Text(
                                            stepDesc,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF4B5563),
                                              height: 1.3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Button always pinned at the bottom ───────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      btnSpacing,
                      14,
                      btnSpacing,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => widget.nextPage,
                            ),
                          );
                          if (context.mounted) {
                            Navigator.pop(context, result);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          "I'm Ready",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
