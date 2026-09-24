import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class ImageCropperPage extends StatefulWidget {
  final XFile image;

  const ImageCropperPage({super.key, required this.image});

  @override
  State<ImageCropperPage> createState() => _ImageCropperPageState();
}

class _ImageCropperPageState extends State<ImageCropperPage> {
  late Offset tl, tr, bl, br;
  bool _isInitialized = false;
  bool _isProcessing = false;
  late Size _imageDisplaySize;
  late Size _rawImageSize;

  @override
  void initState() {
    super.initState();
    _initializePoints();
  }

  Future<void> _initializePoints() async {
    final bytes = await File(widget.image.path).readAsBytes();
    final decoded = await compute(img.decodeImage, bytes);
    if (decoded == null) return;

    _rawImageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());

    // Wait for the UI to be built to get the display size
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final displayWidth = renderBox.size.width;
      final displayHeight =
          renderBox.size.height - 150; // Accounting for bottom bar

      // Fit image into display area while maintaining aspect ratio
      double scale = displayWidth / _rawImageSize.width;
      if (_rawImageSize.height * scale > displayHeight) {
        scale = displayHeight / _rawImageSize.height;
      }

      _imageDisplaySize =
          Size(_rawImageSize.width * scale, _rawImageSize.height * scale);

      setState(() {
        // Default to full image (0 margin) as per user request
        tl = const Offset(5, 5);
        tr = Offset(_imageDisplaySize.width - 5, 5);
        bl = Offset(5, _imageDisplaySize.height - 5);
        br = Offset(_imageDisplaySize.width - 5, _imageDisplaySize.height - 5);
        _isInitialized = true;
      });
    });
  }

  Future<void> _performCrop() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Small delay to ensure UI shows the loader
    await Future.delayed(const Duration(milliseconds: 5));

    try {
      final bytes = await File(widget.image.path).readAsBytes();

      // Move intensive processing to compute isolate
      final String? outPath = await compute(_processImageIsolate, {
        'bytes': bytes,
        'tl': tl,
        'tr': tr,
        'bl': bl,
        'br': br,
        'displayWidth': _imageDisplaySize.width,
        'displayHeight': _imageDisplaySize.height,
        'tempDir': (await getTemporaryDirectory()).path,
      });

      if (outPath != null && mounted) {
        Navigator.pop(context, XFile(outPath));
      }
    } catch (e) {
      debugPrint('Error cropping image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not crop image: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title:
            const Text('Crop Document', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: _isInitialized && !_isProcessing ? _performCrop : null,
          ),
        ],
      ),
      body: _isInitialized
          ? Stack(
              children: [
                Center(
                  child: Container(
                    width: _imageDisplaySize.width,
                    height: _imageDisplaySize.height,
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: FileImage(File(widget.image.path)),
                        fit: BoxFit.contain,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Lines between corners
                        CustomPaint(
                          painter: QuadPainter(tl, tr, bl, br),
                          size: _imageDisplaySize,
                        ),
                        // Draggable handles
                        _buildHandle(
                            tl, (newPos) => setState(() => tl = newPos)),
                        _buildHandle(
                            tr, (newPos) => setState(() => tr = newPos)),
                        _buildHandle(
                            bl, (newPos) => setState(() => bl = newPos)),
                        _buildHandle(
                            br, (newPos) => setState(() => br = newPos)),

                        // Edge midpoints for easier adjustment
                        _buildHandle((tl + tr) / 2, (newPos) {
                          final delta = newPos - (tl + tr) / 2;
                          setState(() {
                            tl += delta;
                            tr += delta;
                          });
                        }),
                        _buildHandle((bl + br) / 2, (newPos) {
                          final delta = newPos - (bl + br) / 2;
                          setState(() {
                            bl += delta;
                            br += delta;
                          });
                        }),
                        _buildHandle((tl + bl) / 2, (newPos) {
                          final delta = newPos - (tl + bl) / 2;
                          setState(() {
                            tl += delta;
                            bl += delta;
                          });
                        }),
                        _buildHandle((tr + br) / 2, (newPos) {
                          final delta = newPos - (tr + br) / 2;
                          setState(() {
                            tr += delta;
                            br += delta;
                          });
                        }),
                      ],
                    ),
                  ),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Please wait...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            )
          : const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }

  Widget _buildHandle(Offset pos, Function(Offset) onUpdate) {
    return Positioned(
      left: pos.dx - 15,
      top: pos.dy - 15,
      child: GestureDetector(
        onPanUpdate: (details) {
          onUpdate(pos + details.delta);
        },
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF444CE7), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuadPainter extends CustomPainter {
  final Offset tl, tr, bl, br;

  QuadPainter(this.tl, this.tr, this.bl, this.br);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF444CE7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    canvas.drawPath(path, paint);

    // Fill with semi-transparent color
    final fillPaint = Paint()
      ..color = const Color(0xFF444CE7).withOpacity(0.1)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant QuadPainter oldDelegate) => true;
}

/// Isolate function for heavy image processing
Future<String?> _processImageIsolate(Map<String, dynamic> params) async {
  try {
    final Uint8List bytes = params['bytes'];
    final Offset tl = params['tl'];
    final Offset tr = params['tr'];
    final Offset bl = params['bl'];
    final Offset br = params['br'];
    final double displayWidth = params['displayWidth'];
    final double displayHeight = params['displayHeight'];
    final String tempDir = params['tempDir'];

    final src = img.decodeImage(bytes);
    if (src == null) return null;

    final scaleX = src.width / displayWidth;
    final scaleY = src.height / displayHeight;

    final pTL = img.Point(tl.dx * scaleX, tl.dy * scaleY);
    final pTR = img.Point(tr.dx * scaleX, tr.dy * scaleY);
    final pBL = img.Point(bl.dx * scaleX, bl.dy * scaleY);
    final pBR = img.Point(br.dx * scaleX, br.dy * scaleY);

    //  Optimized Resolution: 150 DPI is standard for clear document scanning
    const destWidth = 1240;
    const destHeight = 1754;

    final rectified = img.copyRectify(
      src,
      topLeft: pTL,
      topRight: pTR,
      bottomLeft: pBL,
      bottomRight: pBR,
      interpolation: img.Interpolation.linear,
      toImage: img.Image(width: destWidth, height: destHeight),
    );

    final outPath =
        '$tempDir/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final jpgBytes = img.encodeJpg(rectified, quality: 85);
    final file = File(outPath);
    await file.writeAsBytes(jpgBytes);

    return outPath;
  } catch (e) {
    debugPrint('Isolate processing error: $e');
    return null;
  }
}
