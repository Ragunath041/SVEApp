import 'dart:typed_data';

import 'package:camera/camera.dart';

extension Nv21Converter on CameraImage {
  Uint8List getNv21Uint8List() {
    // PATCH: Some Android devices (e.g. Realme RMX3867, OPPO) return NV21
    // frames as a SINGLE plane with all data already packed in planes[0].
    // The original code assumed 3 planes and crashed with RangeError on
    // planes[1] / planes[2] access.
    if (planes.length == 1) {
      // Single-plane device: the full NV21 byte stream is already in planes[0]
      return planes[0].bytes;
    }

    final width = this.width;
    final height = this.height;

    final yPlane = planes[0];
    // Some devices use 2-plane (Y + interleaved UV)
    final uPlane = planes.length > 1 ? planes[1] : null;
    final vPlane = planes.length > 2 ? planes[2] : null;

    // 2-plane case: Y in planes[0], interleaved VU in planes[1]
    if (vPlane == null && uPlane != null) {
      final yBytes = yPlane.bytes;
      final uvBytes = uPlane.bytes; // already interleaved as VU or UV
      final numPixels = (width * height * 1.5).toInt();
      final nv21 = Uint8List(numPixels);
      nv21.setRange(0, yBytes.length, yBytes);
      nv21.setRange(yBytes.length, numPixels, uvBytes);
      return nv21;
    }

    // Standard 3-plane YUV_420_888 → NV21 conversion
    final yBuffer = yPlane.bytes;
    final uBuffer = uPlane!.bytes;
    final vBuffer = vPlane!.bytes;

    final numPixels = (width * height * 1.5).toInt();
    final nv21 = List<int>.filled(numPixels, 0);

    // Full size Y channel and quarter size U+V channels.
    int idY = 0;
    int idUV = width * height;
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    // Copy Y & UV channel.
    // NV21 format is expected to have YYYYVU packaging.
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 0;
    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 0;

    for (int y = 0; y < height; ++y) {
      final uvOffset = y * uvRowStride;
      final yOffset = y * yRowStride;

      for (int x = 0; x < width; ++x) {
        nv21[idY++] = yBuffer[yOffset + x * yPixelStride];

        if (y < uvHeight && x < uvWidth) {
          final bufferIndex = uvOffset + (x * uvPixelStride);
          // V channel
          nv21[idUV++] = vBuffer[bufferIndex];
          // U channel
          nv21[idUV++] = uBuffer[bufferIndex];
        }
      }
    }
    return Uint8List.fromList(nv21);
  }
}
