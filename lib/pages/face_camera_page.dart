import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:face_camera/face_camera.dart';
import 'package:flutter/material.dart';
import 'package:supervisorapp/Services/logging/face_telemetry_log_service.dart';
import '../Services/FaceRecognitionService.dart';

class FaceCameraPage extends StatefulWidget {
  final String title;
  final String? instructionText;
  final bool autoCapture;
  final String? supervisorId;

  /// One of: 'straight' | 'left' | 'right' | 'top' | 'bottom'
  /// Defaults to 'straight' (all angles must be near zero).
  final String poseId;

  const FaceCameraPage({
    super.key,
    this.title = 'Capture Face',
    this.instructionText,
    this.autoCapture = false,
    this.supervisorId,
    this.poseId = 'straight',
  });

  @override
  State<FaceCameraPage> createState() => _FaceCameraPageState();
}

class _FaceCameraPageState extends State<FaceCameraPage> {
  late FaceCameraController _controller;
  Face? _lastDetectedFace;
  bool _isCapturingData = false;
  File? _capturedFile; // Store captured image
  bool _isIOSDelayPassed = !Platform.isIOS;
  String _customGuidanceMessage = '';

  // Stability timer: face must be well-positioned for this long before capture.
  Timer? _stabilityTimer;
  static const Duration _stabilityDuration = Duration(
    milliseconds: 1500,
  ); // 1.5s

  // Tracks whether the face is currently considered well-positioned
  bool _faceIsStable = false;

  @override
  void initState() {
    super.initState();
    _controller = FaceCameraController(
      autoCapture: false, // Managed by us for stability
      imageResolution: ImageResolution.medium,
      defaultCameraLens: CameraLens.front,
      defaultFlashMode: CameraFlashMode.off,
      enableAudio: false,
      performanceMode: FaceDetectorMode.fast,
      ignoreFacePositioning: true,
      onCapture: (File? image) async {
        if (image != null && !_isCapturingData) {
          if (mounted) setState(() => _capturedFile = image);
          await _handleSuccessfulCapture(image);
        }
      },
      onFaceDetected: (Face? face) {
        if (Platform.isIOS && !_isIOSDelayPassed) return;
        _lastDetectedFace = face;

        if (!widget.autoCapture || _isCapturingData) return;

        final bool hasGlare = _controller.value.detectedFace?.hasGlare ?? false;
        final isWellPositioned = _isFaceWellPositioned(face, hasGlare: hasGlare);

        if (isWellPositioned && !_faceIsStable) {
          _faceIsStable = true;
          debugPrint('🎯 Face stable & clear - starting 1.5s capture countdown...');
          _stabilityTimer?.cancel();
          _stabilityTimer = Timer(_stabilityDuration, () {
            if (mounted && !_isCapturingData) {
              final bool currentGlare = _controller.value.detectedFace?.hasGlare ?? false;
              // Robust final check: verify the face is STILL well-positioned and glare-free right before capture
              if (_isFaceWellPositioned(_lastDetectedFace, hasGlare: currentGlare)) {
                debugPrint('📸 Stability timer finished - capturing now!');
                _stabilityTimer = null;
                _controller.captureImage();
              } else {
                debugPrint(
                  '❌ Capture cancelled: face moved or glare detected right before capture.',
                );
                _faceIsStable = false;
                _stabilityTimer = null;
              }
            }
          });
        } else if (!isWellPositioned && _faceIsStable) {
          _faceIsStable = false;
          _stabilityTimer?.cancel();
          _stabilityTimer = null;
          debugPrint('❌ Face moved or lost - capture timer cancelled');
        }
      },
    );

    // Start the image stream for face detection
    _initializeController();

    if (Platform.isIOS) {
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          setState(() {
            _isIOSDelayPassed = true;
          });
        }
      });
    }
  }

  void _showModelErrorDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.red.shade600,
              size: 28,
            ),
            const SizedBox(width: 10),
            const Text(
              'Model Error',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'The offline face recognition model failed to initialize. '
          'Please ensure your device has sufficient storage and internet connection for the first-time setup, then try again.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Close error dialog

              // Show a loading indicator dialog
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (loadingContext) => const Center(
                  child: Card(
                    color: Colors.white,
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF6941C6),
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Initializing AI Model...',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              try {
                await FaceRecognitionServiceEnhanced.initialize();
                if (!mounted) return;
                Navigator.of(context).pop(); // Close loading dialog
                if (FaceRecognitionServiceEnhanced.isInitialized) {
                  _initializeController(); // Success: start stream
                } else {
                  _showModelErrorDialog();
                }
              } catch (e) {
                if (!mounted) return;
                Navigator.of(context).pop(); // Close loading dialog
                _showModelErrorDialog();
              }
            },
            child: const Text(
              'Retry',
              style: TextStyle(
                color: Color(0xFF6941C6),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Close error dialog
              Navigator.pop(context); // Go back to previous page
            },
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeController() async {
    try {
      // Quietly try to initialize if it's missing/not initialized
      if (!FaceRecognitionServiceEnhanced.isInitialized) {
        debugPrint(
          '⚠️ Model not initialized. Attempting quiet initialization...',
        );
        try {
          await FaceRecognitionServiceEnhanced.initialize();
        } catch (e) {
          debugPrint('❌ Silent initialization failed: $e');
        }
      }

      // If it still fails, show the warning popup right here on the camera page!
      if (!FaceRecognitionServiceEnhanced.isInitialized) {
        debugPrint('❌ Model still missing. Prompting user.');
        _showModelErrorDialog();
        return;
      }

      await _controller.startImageStream();
      debugPrint('✅ Face detection image stream started');
    } catch (e) {
      debugPrint('❌ Error starting image stream: $e');
    }
  }

  @override
  void dispose() {
    _stabilityTimer?.cancel();
    _controller.stopImageStream().then((_) => _controller.dispose());
    super.dispose();
  }

  /// Returns true if the face meets the relaxed well-positioned criteria and is free of optical glare.
  bool _isFaceWellPositioned(Face? face, {bool hasGlare = false}) {
    if (face == null) {
      _customGuidanceMessage =
          widget.instructionText ?? 'Position your face inside the frame';
      return false;
    }

    // 0. Spectacle Glare / Reflection check
    if (hasGlare) {
      _customGuidanceMessage = 'Spectacle glare detected! Tilt head slightly';
      return false;
    }

    //  1. Side-to-side (Y-Axis): Relaxed to 12° for better compatibility
    if (face.headEulerAngleY != null && face.headEulerAngleY!.abs() > 12) {
      _customGuidanceMessage = 'Look straight at the camera';
      return false;
    }

    //  2. Tilt (Z-Axis):
    // On iOS, we use 20° to prevent "non-proper" angles while remaining easy to capture.
    // On Android, we keep a slightly stricter 12°.
    final double zThreshold = Platform.isIOS ? 20.0 : 12.0;
    if (face.headEulerAngleZ != null &&
        face.headEulerAngleZ!.abs() > zThreshold) {
      _customGuidanceMessage = 'Look straight at the camera';
      return false;
    }

    //  3. Up/Down (X-Axis):
    // Prevents captures where the student is looking too far up or down (looking at ceiling/lap)
    if (face.headEulerAngleX != null && face.headEulerAngleX!.abs() > 15) {
      _customGuidanceMessage = 'Look straight at the camera';
      return false;
    }

    //  4. Distance / Face Size (Ratio-based check using bounding box width)
    final cameraController = _controller.value.cameraController;
    double frameWidth = 480.0; // standard default fallback
    if (cameraController != null &&
        cameraController.value.isInitialized &&
        cameraController.value.previewSize != null) {
      final size = cameraController.value.previewSize!;
      frameWidth = size.width < size.height ? size.width : size.height;
    }

    final double faceWidthRatio = face.boundingBox.width / frameWidth;
    const double minFaceRatio = 0.59;
    const double maxFaceRatio = 0.69;

    if (faceWidthRatio < minFaceRatio) {
      _customGuidanceMessage = 'Too far! Move closer';
      return false;
    } else if (faceWidthRatio > maxFaceRatio) {
      _customGuidanceMessage = 'Too close! Move back';
      return false;
    }

    // Optional: Only check probability if the sensor actually returns it
    if (face.leftEyeOpenProbability != null &&
        face.leftEyeOpenProbability! < 0.3) {
      _customGuidanceMessage = 'Please keep your eyes open';
      return false;
    }
    if (face.rightEyeOpenProbability != null &&
        face.rightEyeOpenProbability! < 0.3) {
      _customGuidanceMessage = 'Please keep your eyes open';
      return false;
    }

    _customGuidanceMessage = 'Perfect! Hold still...';
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!_isCapturingData)
            SmartFaceCamera(
              controller: _controller,
              messageBuilder: (context, detectedFace) {
                _isFaceWellPositioned(
                  detectedFace?.face,
                  hasGlare: detectedFace?.hasGlare ?? false,
                );
                return _buildMessage(_customGuidanceMessage);
              },
              showControls: true,
              showCaptureControl: !widget.autoCapture && !_isCapturingData,
              showFlashControl: false,
              showCameraLensControl: false,
            )
          else if (_capturedFile != null)
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationY(3.14159),
              child: Image.file(
                _capturedFile!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),

          if (_isCapturingData)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Processing Face Capture...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please hold still',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: _isCapturingData ? null : () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(String msg) => Align(
    alignment: const Alignment(
      0,
      0.65,
    ), // Positioned lower down, below the face frame and highly visible
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54, // Elegant dark translucent backing
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 30),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  );

  Future<void> _handleSuccessfulCapture(File imageFile) async {
    try {
      _stabilityTimer?.cancel();
      _stabilityTimer = null;
      if (mounted) setState(() => _isCapturingData = true);

      // Stop stream to free up resources
      try {
        await _controller.stopImageStream();
      } catch (e) {
        debugPrint('Error stopping stream: $e');
      }

      String userId = widget.supervisorId ?? 'Unknown';

      final face = _lastDetectedFace;
      final logAngle = face != null
          ? 'Y:${(face.headEulerAngleY ?? 0).toStringAsFixed(1)} / X:${(face.headEulerAngleX ?? 0).toStringAsFixed(1)}'
          : 'Package-Managed';

      // Log asynchronously
      S3FaceLogService.logFaceEvent(
        bitsId: userId,
        action: widget.title.toLowerCase().contains('register')
            ? 'Register Capture'
            : 'Login Capture',
        status: 'Success (Pkg)',
        deviceModel: Platform.isIOS ? 'iOS' : 'Android',
        size: 'Auto-Stream',
        angle: logAngle,
        center: 'Package-Managed',
        light: 'N/A',
      ).catchError((e) => debugPrint('Error logging face event: $e'));

      if (mounted) {
        Navigator.pop(context, XFile(imageFile.path));
      }
    } catch (e) {
      debugPrint('❌ Error during post-capture processing: $e');
      if (mounted) {
        setState(() => _isCapturingData = false);
      }
    }
  }
}
