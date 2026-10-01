// ignore_for_file: file_names, avoid_print

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import 'decrypted_image_widget.dart';

class QRScannerPage extends StatefulWidget {
  final String supervisorId;

  const QRScannerPage({super.key, required this.supervisorId});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController();

  bool _scanned = false;

  late AnimationController _animController;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() => _scanned = true);
    _controller.stop();
    _animController.stop();

    _showResultDialog(barcode.rawValue!);
  }

  Widget _buildStructuredContent(String rawValue, String? imageUrlKey) {
    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(rawValue);
      if (parsed is Map<String, dynamic>) {
        decoded = parsed;
      }
    } catch (e) {
      debugPrint('[QRScannerPage] QR content is not JSON formatted: $e');
    }

    if (decoded != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final double parentWidth = constraints.maxWidth;
          // Calculate item width for 2-column layout (accounting for spacing)
          final double itemWidth = (parentWidth - 10) / 2;

          final List<Widget> items = [];
          decoded!.forEach((key, val) {
            // Skip the image URL key so it doesn't show in the text grid
            if (key == imageUrlKey) return;

            var readableKey = key
                .replaceAll(RegExp(r'(_|-)'), ' ')
                .split(RegExp(r'(?=[A-Z])|\s'))
                .where((word) => word.isNotEmpty)
                .map(
                  (word) =>
                      word[0].toUpperCase() + word.substring(1).toLowerCase(),
                )
                .join(' ');

            if (readableKey.toLowerCase() == 'time') {
              readableKey = 'Timing';
            }

            // Determine icon based on key
            IconData itemIcon = Icons.info_outline_rounded;
            final lowerKey = key.toLowerCase();
            if (lowerKey.contains('name')) {
              itemIcon = Icons.person_outline_rounded;
            } else if (lowerKey.contains('id') ||
                lowerKey.contains('reg') ||
                lowerKey.contains('roll') ||
                lowerKey.contains('num')) {
              itemIcon = Icons.badge_outlined;
            } else if (lowerKey.contains('course') ||
                lowerKey.contains('subject') ||
                lowerKey.contains('exam') ||
                lowerKey.contains('class') ||
                lowerKey.contains('code')) {
              itemIcon = Icons.menu_book_rounded;
            } else if (lowerKey.contains('session') ||
                lowerKey.contains('timing') ||
                lowerKey.contains('hour')) {
              itemIcon = Icons.schedule_rounded;
            } else if (lowerKey.contains('date')) {
              itemIcon = Icons.calendar_today_rounded;
            } else if (lowerKey.contains('center') ||
                lowerKey.contains('centre') ||
                lowerKey.contains('room') ||
                lowerKey.contains('hall')) {
              itemIcon = Icons.room_outlined;
            }

            items.add(
              Container(
                width: itemWidth,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEEF2F6)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF444CE7).withValues(alpha: 0.01),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF444CE7).withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        itemIcon,
                        color: const Color(0xFF444CE7),
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            readableKey,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            val?.toString() ?? 'N/A',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          });

          return Wrap(spacing: 10, runSpacing: 10, children: items);
        },
      );
    }

    // Fallback: Plain text display
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notes_rounded, color: Colors.grey, size: 16),
              SizedBox(width: 8),
              Text(
                'Scanned Code Raw Content',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            rawValue,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  MapEntry<String, String>? _findImageUrlEntry(String rawValue) {
    try {
      final parsed = jsonDecode(rawValue);
      if (parsed is Map<String, dynamic>) {
        for (final key in parsed.keys) {
          final lowerKey = key.toLowerCase();
          if (lowerKey.contains('url') ||
              lowerKey.contains('photo') ||
              lowerKey.contains('image')) {
            final val = parsed[key]?.toString();
            if (val != null &&
                (val.startsWith('http://') || val.startsWith('https://'))) {
              return MapEntry(key, val);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[QRScannerPage] Error detecting image URL in QR: $e');
    }
    return null;
  }

  ScannedStudentData _parseStudentData(String rawValue) {
    String name = '';
    String bitsId = '';
    String organization = '';
    String center = '';
    String courseCode = '';
    String courseName = '';
    String date = '';
    String time = '';
    String imageUrl = '';

    try {
      final parsed = jsonDecode(rawValue);
      if (parsed is Map<String, dynamic>) {
        parsed.forEach((key, val) {
          final lowerKey = key.toLowerCase();
          final stringVal = val?.toString() ?? '';

          if (lowerKey.contains('name') && !lowerKey.contains('course')) {
            name = stringVal;
          } else if (lowerKey.contains('bits') ||
              lowerKey.contains('id') ||
              lowerKey.contains('reg') ||
              lowerKey.contains('roll')) {
            bitsId = stringVal;
          } else if (lowerKey.contains('org') || lowerKey.contains('company')) {
            organization = stringVal;
          } else if (lowerKey.contains('center') ||
              lowerKey.contains('centre')) {
            center = stringVal;
          } else if (lowerKey.contains('coursecode') ||
              (lowerKey.contains('course') && lowerKey.contains('code'))) {
            courseCode = stringVal;
          } else if (lowerKey.contains('coursename') ||
              (lowerKey.contains('course') && lowerKey.contains('name'))) {
            courseName = stringVal;
          } else if (lowerKey.contains('date')) {
            date = stringVal;
          } else if (lowerKey.contains('time') ||
              lowerKey.contains('session')) {
            time = stringVal;
          } else if (lowerKey.contains('url') ||
              lowerKey.contains('photo') ||
              lowerKey.contains('image')) {
            imageUrl = stringVal;
          }
        });
      }
    } catch (e) {
      debugPrint('[QRScannerPage] Error parsing student data: $e');
    }

    return ScannedStudentData(
      name: name,
      bitsId: bitsId,
      organization: organization,
      center: center,
      courseCode: courseCode,
      courseName: courseName,
      date: date,
      time: time,
      imageUrl: imageUrl,
      supervisorId: widget.supervisorId,
    );
  }

  void _showResultDialog(String value) {
    final imageEntry = _findImageUrlEntry(value);
    final imageUrl = imageEntry?.value;
    final imageUrlKey = imageEntry?.key;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with image or gradient icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    if (imageUrl != null)
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF444CE7),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF444CE7,
                              ).withValues(alpha: 0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: DecryptedImageWidget(
                          imageUrl: imageUrl,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          shape: BoxShape.circle,
                        ),
                      )
                    else
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF818CF8), Color(0xFF444CE7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF444CE7,
                              ).withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'QR Code Scanned Successfully',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),

              // Content Area (Details list without scrolling)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: _buildStructuredContent(value, imageUrlKey),
              ),

              // Actions Panel
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                  border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                        label: const Text(
                          'Scan Again',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() => _scanned = false);
                          _controller.start();
                          _animController.repeat(reverse: true);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF818CF8), Color(0xFF444CE7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF444CE7,
                              ).withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Confirm',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          onPressed: () {
                            final studentData = _parseStudentData(value);
                            print('--- SCANNED STUDENT DATA ---');
                            print(studentData.toString());
                            print('----------------------------');

                            Navigator.of(context).pop();
                            Navigator.of(context).pop(studentData);
                          },
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
    );
  }

  @override
  Widget build(BuildContext context) {
    const cutoutSize = 260.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Student Authentication',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          _ScanOverlay(cutoutSize: cutoutSize, scanAnimation: _scanAnimation),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.qr_code_scanner,
                    color: Colors.white54,
                    size: 32,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _scanned
                        ? 'QR Code detected!'
                        : "Point the camera at the student's QR code",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay widget
// ---------------------------------------------------------------------------

class _ScanOverlay extends StatelessWidget {
  final double cutoutSize;
  final Animation<double> scanAnimation;

  const _ScanOverlay({required this.cutoutSize, required this.scanAnimation});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cutoutTop = (size.height - cutoutSize) / 2 - 60;
    final cutoutLeft = (size.width - cutoutSize) / 2;
    const cornerLen = 28.0;
    const cornerThick = 4.0;
    const cornerRadius = 10.0;
    const cornerColor = Color(0xFF7882EB);

    return Stack(
      children: [
        // Dark scrim with transparent cutout
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.55),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Positioned(
                top: cutoutTop,
                left: cutoutLeft,
                child: Container(
                  width: cutoutSize,
                  height: cutoutSize,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(cornerRadius),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Corners
        for (final placement in [
          (isTop: true, isLeft: true),
          (isTop: true, isLeft: false),
          (isTop: false, isLeft: true),
          (isTop: false, isLeft: false),
        ])
          Positioned(
            top: placement.isTop
                ? cutoutTop
                : cutoutTop + cutoutSize - cornerLen,
            left: placement.isLeft
                ? cutoutLeft
                : cutoutLeft + cutoutSize - cornerLen,
            child: SizedBox(
              width: cornerLen,
              height: cornerLen,
              child: CustomPaint(
                painter: _CornerPainter(
                  color: cornerColor,
                  thickness: cornerThick,
                  radius: cornerRadius,
                  isTop: placement.isTop,
                  isLeft: placement.isLeft,
                ),
              ),
            ),
          ),

        // Scan line
        Positioned(
          top: cutoutTop,
          left: cutoutLeft,
          child: AnimatedBuilder(
            animation: scanAnimation,
            builder: (_, __) => SizedBox(
              width: cutoutSize,
              height: cutoutSize,
              child: Align(
                alignment: Alignment(0, scanAnimation.value * 2 - 1),
                child: Container(
                  height: 2,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        cornerColor,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Corner painter
// ---------------------------------------------------------------------------

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final double radius;
  final bool isTop;
  final bool isLeft;

  const _CornerPainter({
    required this.color,
    required this.thickness,
    required this.radius,
    required this.isTop,
    required this.isLeft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final w = size.width;
    final h = size.height;

    if (isTop && isLeft) {
      path.moveTo(0, h);
      path.lineTo(0, radius);
      path.arcToPoint(Offset(radius, 0), radius: Radius.circular(radius));
      path.lineTo(w, 0);
    } else if (isTop && !isLeft) {
      path.moveTo(0, 0);
      path.lineTo(w - radius, 0);
      path.arcToPoint(Offset(w, radius), radius: Radius.circular(radius));
      path.lineTo(w, h);
    } else if (!isTop && isLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, h - radius);
      path.arcToPoint(Offset(radius, h), radius: Radius.circular(radius));
      path.lineTo(w, h);
    } else {
      path.moveTo(0, h);
      path.lineTo(w - radius, h);
      path.arcToPoint(Offset(w, h - radius), radius: Radius.circular(radius));
      path.lineTo(w, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

class ScannedStudentData {
  final String name;
  final String bitsId;
  final String organization;
  final String center;
  final String courseCode;
  final String courseName;
  final String date;
  final String time;
  final String imageUrl;
  final String supervisorId;

  const ScannedStudentData({
    required this.name,
    required this.bitsId,
    required this.organization,
    required this.center,
    required this.courseCode,
    required this.courseName,
    required this.date,
    required this.time,
    required this.imageUrl,
    required this.supervisorId,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'bitsId': bitsId,
      'organization': organization,
      'center': center,
      'courseCode': courseCode,
      'courseName': courseName,
      'examDate': date,
      'examTiming': time,
      'imageUrl': imageUrl,
      'supervisorId': supervisorId,
    };
  }

  @override
  String toString() {
    return 'ScannedStudentData(${toJson().toString()})';
  }
}
