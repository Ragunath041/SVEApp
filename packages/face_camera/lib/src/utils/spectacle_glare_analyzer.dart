import 'dart:io' show Platform;
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Result of a spectacle / lens-reflection analysis.
class GlareAnalysisResult {
  /// True when a reflection blob was found on either lens.
  final bool hasGlare;

  /// Worst signal normalised by its own threshold. >= 1.0 means glare.
  final double glareScore;

  final String message;

  /// Raw blob coverage (fraction of the eye circle) per signal, for logging.
  final double whiteScore;
  final double tintScore;
  final double greenScore;

  /// False when the camera buffer had no chroma (Y-only), so only the white
  /// hotspot signal could run.
  final bool chromaAvailable;

  const GlareAnalysisResult({
    required this.hasGlare,
    required this.glareScore,
    this.message = '',
    this.whiteScore = 0.0,
    this.tintScore = 0.0,
    this.greenScore = 0.0,
    this.chromaAvailable = true,
  });

  static const GlareAnalysisResult none = GlareAnalysisResult(
    hasGlare: false,
    glareScore: 0.0,
  );
}

/// Debounces the raw per-frame glare flag so the UI/timers don't flicker.
class GlareSmoother {
  GlareSmoother({this.onFrames = 2, this.offFrames = 6});

  /// Consecutive glare frames needed to switch ON.
  final int onFrames;

  /// Consecutive clean frames needed to switch OFF.
  final int offFrames;

  int _on = 0;
  int _off = 0;
  bool _state = false;

  bool get state => _state;

  bool update(bool raw) {
    if (raw) {
      _on++;
      _off = 0;
      if (_on >= onFrames) _state = true;
    } else {
      _off++;
      _on = 0;
      if (_off >= offFrames) _state = false;
    }
    return _state;
  }

  void reset() {
    _on = 0;
    _off = 0;
    _state = false;
  }
}

/// Detects reflections on spectacle lenses using three independent signals,
/// each evaluated inside a circle around each eye:
///
///  1. WHITE  - clipped, neutral-coloured specular hotspot (bulbs, windows).
///  2. TINT   - blue / violet / cyan reflection (phone screen, blue-cut
///              coating). Detected via high Cb. Skin never exceeds Cb ~125.
///  3. GREEN  - green AR-coating reflection. Detected via very low Cr.
///
/// Every signal is "largest connected blob / samples in the circle", not a
/// count of scattered pixels, so skin shine, sclera and tiny corneal
/// catch-lights do not trigger it.
///
/// Works on: Android NV21 (single plane or 2/3 plane), iOS BGRA, and decoded
/// still images (via [analyzeStill]).
class SpectacleGlareAnalyzer {
  // ---------------------------------------------------------------------------
  // Tunables. Calibrate with the debug log (white= tint= green=).
  // ---------------------------------------------------------------------------
  static const double whiteThreshold =
      0.030; // 3.0% of eye circle (corneal catchlight is <1.5%, lens glare is >=5%)
  static const double tintThreshold = 0.045; // 4.5% (screen reflection is >=8%)
  static const double greenThreshold =
      0.045; // 4.5% (green AR reflection is >=8%)
  static const int minBlobSamples =
      12; // filters out tiny corneal catchlights & skin shine

  static const int whiteLuma = 240;
  static const int whiteNeutralTol = 16; // |Cb-128|,|Cr-128| <= tol
  static const int blueCb = 148;
  static const int minTintLuma = 75;
  static const int greenCrMax = 110;
  static const int greenCbMax = 125;
  static const int minGreenLuma = 80;

  /// Eye circle radius as a fraction of the face bounding-box width.
  static const double radiusFactor = 0.18;

  static int _debugFrame = 0;

  /// Latest numbers, for an on-screen debug overlay (see usage notes).
  static String lastDebug = '';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Live camera frame (Android NV21/YUV420, iOS BGRA).
  static GlareAnalysisResult analyze({
    required CameraImage image,
    required Face? face,
    required InputImageRotation? rotation,
  }) {
    if (face == null || image.planes.isEmpty) return GlareAnalysisResult.none;

    try {
      _Pixels? px = _pixelsFor(image);
      if (px == null) return GlareAnalysisResult.none;

      final int w = image.width;
      final int h = image.height;

      // Skin always has Cr > Cb. If the buffer says otherwise, the U/V order
      // on this device is the opposite of what we assumed (NV12 vs NV21), so
      // swap the channels. Without this, orange-brown skin reads as "blue".
      bool swapped = false;
      if (px.hasChroma) {
        final box = face.boundingBox;
        final centre = _mapCoord(
          Point<int>(box.center.dx.round(), box.center.dy.round()),
          rotation,
          w,
          h,
        );
        swapped = _chromaSwapped(px, centre, box.width, w, h);
        if (swapped) px = _SwappedPixels(px);
      }

      final eyes = _eyePoints(face);
      final left = _mapCoord(eyes[0], rotation, w, h);
      final right = _mapCoord(eyes[1], rotation, w, h);

      // Face width is measured in upright space, which has the same pixel
      // scale as the raw buffer.
      final double radius = max(10.0, face.boundingBox.width * radiusFactor);

      final result = _evaluate(px, left, right, radius, w, h);

      if (kDebugMode) {
        _debugFrame++;
        if (_debugFrame % 8 == 0) {
          debugPrint(
            '👓 [Glare] white=${(result.whiteScore * 100).toStringAsFixed(1)}% '
            'tint=${(result.tintScore * 100).toStringAsFixed(1)}% '
            'green=${(result.greenScore * 100).toStringAsFixed(1)}% '
            'chroma=${result.chromaAvailable} swapped=$swapped '
            'planes=${image.planes.length} fmt=${image.format.raw} '
            '-> ${result.hasGlare ? "GLARE ⚠️" : "OK ✅"}',
          );
        }
      }
      return result;
    } catch (e, st) {
      if (kDebugMode) debugPrint('👓 [Glare] analysis error: $e\n$st');
      return GlareAnalysisResult.none;
    }
  }

  /// Decoded still image (upright, rotation already baked in).
  ///
  /// [rgbAt] must return 0xRRGGBB for pixel (x, y).
  /// With package:image 4.x:
  /// ```dart
  /// rgbAt: (x, y) {
  ///   final p = img.getPixel(x, y);
  ///   return (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
  /// }
  /// ```
  static GlareAnalysisResult analyzeStill({
    required Face face,
    required int width,
    required int height,
    required int Function(int x, int y) rgbAt,
  }) {
    try {
      final px = _CallbackPixels(rgbAt, width, height);
      final eyes = _eyePoints(face);
      final left = Point<int>(
        eyes[0].x.clamp(0, width - 1),
        eyes[0].y.clamp(0, height - 1),
      );
      final right = Point<int>(
        eyes[1].x.clamp(0, width - 1),
        eyes[1].y.clamp(0, height - 1),
      );
      final double radius = max(10.0, face.boundingBox.width * radiusFactor);
      final result = _evaluate(px, left, right, radius, width, height);
      if (kDebugMode) {
        debugPrint(
          '👓 [Glare/Still] white=${(result.whiteScore * 100).toStringAsFixed(1)}% '
          'tint=${(result.tintScore * 100).toStringAsFixed(1)}% '
          'green=${(result.greenScore * 100).toStringAsFixed(1)}% '
          '-> ${result.hasGlare ? "GLARE ⚠️" : "OK ✅"}',
        );
      }
      return result;
    } catch (e, st) {
      if (kDebugMode) debugPrint('👓 [Glare/Still] error: $e\n$st');
      return GlareAnalysisResult.none;
    }
  }

  // ---------------------------------------------------------------------------
  // Core
  // ---------------------------------------------------------------------------

  static GlareAnalysisResult _evaluate(
    _Pixels px,
    Point<int> left,
    Point<int> right,
    double radius,
    int w,
    int h,
  ) {
    final l = _scoreEye(px, left, radius, w, h);
    final r = _scoreEye(px, right, radius, w, h);

    final double white = max(l[0], r[0]);
    final double tint = max(l[1], r[1]);
    final double green = max(l[2], r[2]);

    lastDebug =
        'buf ${w}x$h  L(${left.x},${left.y})  R(${right.x},${right.y})  r=${radius.round()}\n'
        'L  Y/Cb/Cr = ${l[3].toStringAsFixed(0)}/${l[4].toStringAsFixed(0)}/${l[5].toStringAsFixed(0)}\n'
        'R  Y/Cb/Cr = ${r[3].toStringAsFixed(0)}/${r[4].toStringAsFixed(0)}/${r[5].toStringAsFixed(0)}\n'
        'white ${(white * 100).toStringAsFixed(1)}%  '
        'tint ${(tint * 100).toStringAsFixed(1)}%  '
        'green ${(green * 100).toStringAsFixed(1)}%';

    final double wn = white / whiteThreshold;
    final double tn = tint / tintThreshold;
    final double gn = green / greenThreshold;
    final double worst = max(wn, max(tn, gn));
    final bool hasGlare = worst >= 1.0;

    String message = '';
    if (hasGlare) {
      if (tn >= wn && tn >= gn) {
        message = 'Screen reflection on glasses. Lower screen brightness or '
            'tilt your chin down slightly';
      } else {
        message = 'Glare on glasses. Lower your chin slightly or move away '
            'from the light';
      }
    }

    return GlareAnalysisResult(
      hasGlare: hasGlare,
      glareScore: worst,
      message: message,
      whiteScore: white,
      tintScore: tint,
      greenScore: green,
      chromaAvailable: px.hasChroma,
    );
  }

  /// Returns [white, tint, green] blob fractions for one eye circle.
  static List<double> _scoreEye(
    _Pixels px,
    Point<int> c,
    double radius,
    int w,
    int h,
  ) {
    final int rad = max(6, radius.round());
    // Normalise the grid to ~44x44 samples regardless of resolution, so cost
    // is constant (~1500 samples per eye) on 480p streams and 12MP stills.
    final int step = max(1, (2 * rad / 44).ceil());
    final int n = (2 * rad) ~/ step + 1;
    final int rSq = rad * rad;

    final Uint8List flags = Uint8List(n * n);
    int total = 0;
    int clipped = 0;
    int sumY = 0, sumCb = 0, sumCr = 0;
    final bool chroma = px.hasChroma;

    for (int gy = 0; gy < n; gy++) {
      final int dy = gy * step - rad;
      final int py = c.y + dy;
      if (py < 0 || py >= h) continue;
      for (int gx = 0; gx < n; gx++) {
        final int dx = gx * step - rad;
        if (dx * dx + dy * dy > rSq) continue;
        final int pxX = c.x + dx;
        if (pxX < 0 || pxX >= w) continue;

        final int v = px.ycc(pxX, py);
        if (v < 0) continue;
        total++;

        final int y = (v >> 16) & 0xFF;
        final int cb = (v >> 8) & 0xFF;
        final int cr = v & 0xFF;
        sumY += y;
        sumCb += cb;
        sumCr += cr;

        int f = 0;
        if (y >= whiteLuma) {
          clipped++;
          if ((cb - 128).abs() <= whiteNeutralTol &&
              (cr - 128).abs() <= whiteNeutralTol) {
            f |= _kWhite;
          }
        }
        if (chroma) {
          if (cb >= blueCb && y >= minTintLuma) {
            f |= _kTint;
          } else if (cr <= greenCrMax &&
              cb <= greenCbMax &&
              y >= minGreenLuma) {
            f |= _kGreen;
          }
        }
        flags[gy * n + gx] = f | _kValid;
      }
    }

    if (total < 20) return const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0];

    final Uint8List visited = Uint8List(n * n);
    final List<int> stack = <int>[];

    // If most of the circle is clipped it is over-exposure, not a lens hotspot.
    final bool blownOut = clipped / total > 0.5;

    double frac(int mask) {
      final int blob = _largestBlob(flags, visited, stack, n, mask);
      return blob >= minBlobSamples ? blob / total : 0.0;
    }

    final double white = blownOut ? 0.0 : frac(_kWhite);
    final double tint = chroma ? frac(_kTint) : 0.0;
    final double green = chroma ? frac(_kGreen) : 0.0;
    return [white, tint, green, sumY / total, sumCb / total, sumCr / total];
  }

  static const int _kValid = 1;
  static const int _kWhite = 2;
  static const int _kTint = 4;
  static const int _kGreen = 8;

  /// Largest 4-connected component of cells carrying [mask]. Iterative.
  static int _largestBlob(
    Uint8List flags,
    Uint8List visited,
    List<int> stack,
    int n,
    int mask,
  ) {
    for (int i = 0; i < visited.length; i++) {
      visited[i] = 0;
    }
    int best = 0;
    for (int i = 0; i < flags.length; i++) {
      if ((flags[i] & mask) == 0 || visited[i] != 0) continue;
      int size = 0;
      stack.add(i);
      visited[i] = 1;
      while (stack.isNotEmpty) {
        final int k = stack.removeLast();
        size++;
        final int x = k % n;
        final int y = k ~/ n;
        if (x > 0) {
          final int nk = k - 1;
          if (visited[nk] == 0 && (flags[nk] & mask) != 0) {
            visited[nk] = 1;
            stack.add(nk);
          }
        }
        if (x < n - 1) {
          final int nk = k + 1;
          if (visited[nk] == 0 && (flags[nk] & mask) != 0) {
            visited[nk] = 1;
            stack.add(nk);
          }
        }
        if (y > 0) {
          final int nk = k - n;
          if (visited[nk] == 0 && (flags[nk] & mask) != 0) {
            visited[nk] = 1;
            stack.add(nk);
          }
        }
        if (y < n - 1) {
          final int nk = k + n;
          if (visited[nk] == 0 && (flags[nk] & mask) != 0) {
            visited[nk] = 1;
            stack.add(nk);
          }
        }
      }
      if (size > best) best = size;
    }
    return best;
  }

  /// True when the sampled face centre has Cb > Cr, which skin never does.
  static bool _chromaSwapped(
      _Pixels px, Point<int> c, double faceWidth, int w, int h) {
    final int rad = max(8, (faceWidth * 0.22).round());
    final int step = max(1, rad ~/ 8);
    int n = 0;
    int diff = 0;
    for (int dy = -rad; dy <= rad; dy += step) {
      final int py = c.y + dy;
      if (py < 0 || py >= h) continue;
      for (int dx = -rad; dx <= rad; dx += step) {
        final int x = c.x + dx;
        if (x < 0 || x >= w) continue;
        final int v = px.ycc(x, py);
        if (v < 0) continue;
        final int y = (v >> 16) & 0xFF;
        if (y < 50 || y > 220) continue;
        n++;
        diff += ((v >> 8) & 0xFF) - (v & 0xFF);
      }
    }
    return n >= 20 && diff / n > 4;
  }

  // ---------------------------------------------------------------------------
  // Geometry
  // ---------------------------------------------------------------------------

  /// [left, right] eye centres in ML Kit (upright image) coordinates.
  static List<Point<int>> _eyePoints(Face face) {
    final box = face.boundingBox;
    final int defaultY = (box.top + box.height * 0.40).round();
    final lm = face.landmarks[FaceLandmarkType.leftEye];
    final rm = face.landmarks[FaceLandmarkType.rightEye];
    final Point<int> left = lm != null
        ? Point<int>(lm.position.x, lm.position.y)
        : Point<int>((box.left + box.width * 0.30).round(), defaultY);
    final Point<int> right = rm != null
        ? Point<int>(rm.position.x, rm.position.y)
        : Point<int>((box.left + box.width * 0.70).round(), defaultY);
    return [left, right];
  }

  /// Maps a point from ML Kit's upright space back into the raw camera buffer.
  /// (Inverse of the rotation passed to ML Kit.)
  static Point<int> _mapCoord(
      Point<int> pt, InputImageRotation? rot, int w, int h) {
    int x = pt.x;
    int y = pt.y;
    switch (rot) {
      case InputImageRotation.rotation90deg:
        x = pt.y;
        y = h - 1 - pt.x;
        break;
      case InputImageRotation.rotation180deg:
        x = w - 1 - pt.x;
        y = h - 1 - pt.y;
        break;
      case InputImageRotation.rotation270deg:
        x = w - 1 - pt.y;
        y = pt.x;
        break;
      default:
        break;
    }
    return Point<int>(x.clamp(0, w - 1), y.clamp(0, h - 1));
  }

  // ---------------------------------------------------------------------------
  // Pixel access
  // ---------------------------------------------------------------------------

  static _Pixels? _pixelsFor(CameraImage image) {
    final Plane p0 = image.planes[0];
    final int h = image.height;

    if (Platform.isIOS) {
      if (p0.bytes.length < p0.bytesPerRow * h) return null;
      return _BgraPixels(p0.bytes, p0.bytesPerRow);
    }

    final int stride = p0.bytesPerRow;

    if (image.planes.length >= 3) {
      final u = image.planes[1];
      final v = image.planes[2];
      return _Yuv3Pixels(
        p0.bytes,
        stride,
        u.bytes,
        u.bytesPerRow,
        u.bytesPerPixel ?? 1,
        v.bytes,
        v.bytesPerRow,
        v.bytesPerPixel ?? 1,
      );
    }
    if (image.planes.length == 2) {
      final uv = image.planes[1];
      return _Nv21TwoPlanePixels(p0.bytes, stride, uv.bytes, uv.bytesPerRow);
    }
    // Single plane: packed NV21 (Y then interleaved VU), as on Realme/OPPO.
    if (p0.bytes.length >= stride * h * 3 ~/ 2) {
      return _Nv21PackedPixels(p0.bytes, stride, h);
    }
    // Y only: no chroma available, white-hotspot signal only.
    return _YOnlyPixels(p0.bytes, stride);
  }
}

// =============================================================================
// Pixel samplers. ycc() returns (Y << 16) | (Cb << 8) | Cr, or -1 if invalid.
// =============================================================================

abstract class _Pixels {
  bool get hasChroma => true;
  int ycc(int x, int y);
}

int _c8(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

int _fromRgb(int r, int g, int b) {
  final int y = (77 * r + 150 * g + 29 * b) >> 8;
  final int cb = 128 + ((-43 * r - 85 * g + 128 * b) >> 8);
  final int cr = 128 + ((128 * r - 107 * g - 21 * b) >> 8);
  return (_c8(y) << 16) | (_c8(cb) << 8) | _c8(cr);
}

class _BgraPixels extends _Pixels {
  _BgraPixels(this.b, this.stride);
  final Uint8List b;
  final int stride;

  @override
  int ycc(int x, int y) {
    final int o = y * stride + x * 4;
    if (o + 2 >= b.length) return -1;
    return _fromRgb(b[o + 2], b[o + 1], b[o]);
  }
}

class _CallbackPixels extends _Pixels {
  _CallbackPixels(this.rgbAt, this.w, this.h);
  final int Function(int x, int y) rgbAt;
  final int w;
  final int h;

  @override
  int ycc(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return -1;
    final int p = rgbAt(x, y);
    return _fromRgb((p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF);
  }
}

class _Nv21PackedPixels extends _Pixels {
  _Nv21PackedPixels(this.b, this.stride, this.h);
  final Uint8List b;
  final int stride;
  final int h;

  @override
  int ycc(int x, int y) {
    final int yo = y * stride + x;
    final int uvo = stride * h + (y >> 1) * stride + (x & ~1);
    if (uvo + 1 >= b.length) return -1;
    // NV21 = V then U.
    return (b[yo] << 16) | (b[uvo + 1] << 8) | b[uvo];
  }
}

class _Nv21TwoPlanePixels extends _Pixels {
  _Nv21TwoPlanePixels(this.yb, this.yStride, this.uv, this.uvStride);
  final Uint8List yb;
  final int yStride;
  final Uint8List uv;
  final int uvStride;

  @override
  int ycc(int x, int y) {
    final int yo = y * yStride + x;
    final int uvo = (y >> 1) * uvStride + (x & ~1);
    if (yo >= yb.length || uvo + 1 >= uv.length) return -1;
    return (yb[yo] << 16) | (uv[uvo + 1] << 8) | uv[uvo];
  }
}

class _Yuv3Pixels extends _Pixels {
  _Yuv3Pixels(
    this.yb,
    this.yStride,
    this.ub,
    this.uStride,
    this.uPix,
    this.vb,
    this.vStride,
    this.vPix,
  );
  final Uint8List yb;
  final int yStride;
  final Uint8List ub;
  final int uStride;
  final int uPix;
  final Uint8List vb;
  final int vStride;
  final int vPix;

  @override
  int ycc(int x, int y) {
    final int yo = y * yStride + x;
    final int uo = (y >> 1) * uStride + (x >> 1) * uPix;
    final int vo = (y >> 1) * vStride + (x >> 1) * vPix;
    if (yo >= yb.length || uo >= ub.length || vo >= vb.length) return -1;
    return (yb[yo] << 16) | (ub[uo] << 8) | vb[vo];
  }
}

class _YOnlyPixels extends _Pixels {
  _YOnlyPixels(this.b, this.stride);
  final Uint8List b;
  final int stride;

  @override
  bool get hasChroma => false;

  @override
  int ycc(int x, int y) {
    final int o = y * stride + x;
    if (o >= b.length) return -1;
    return (b[o] << 16) | (128 << 8) | 128;
  }
}

/// Swaps Cb and Cr of the wrapped sampler.
class _SwappedPixels extends _Pixels {
  _SwappedPixels(this.inner);
  final _Pixels inner;

  @override
  bool get hasChroma => inner.hasChroma;

  @override
  int ycc(int x, int y) {
    final int v = inner.ycc(x, y);
    if (v < 0) return v;
    return (v & 0xFF0000) | ((v & 0xFF) << 8) | ((v >> 8) & 0xFF);
  }
}
