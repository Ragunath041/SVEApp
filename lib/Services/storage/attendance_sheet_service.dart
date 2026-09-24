import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/security/image_encryption_service.dart';
import 's3_transfer_helper.dart';

/// Handles uploading scanned physical attendance sheets to S3.
class AttendanceSheetService {
  static const String _attendanceBucket = 'bits-attendance';

  /// Upload Attendance Sheet Images to S3
  /// S3 Structure: bits-attendance/{Date}_{Session}_{Centre}/attendancesheet_{index}.png
  static Future<Map<String, dynamic>> uploadAttendanceSheetImages({
    required List<String> imagePaths,
    required String date,
    required String session,
    required String centre,
  }) async {
    try {
      if (imagePaths.isEmpty) {
        return {'success': false, 'error': 'No images selected.'};
      }

      int successCount = 0;
      List<String> errors = [];

      for (int i = 0; i < imagePaths.length; i++) {
        final imagePath = imagePaths[i];
        final file = File(imagePath);

        if (!await file.exists() || await file.length() == 0) {
          errors.add("Image not found or empty (0 bytes): $imagePath");
          continue;
        }

        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          errors.add("Failed to read image bytes: $imagePath");
          continue;
        }

        final encryptedBytes =
            await ImageEncryptionService.encryptImageBytes(bytes);

        // Format: YYYY-MM-DD_Session_Center/attendancesheet_{index}.png
        final key = "${date}_${session}_$centre/attendancesheet_${i + 1}.png";

        debugPrint(
          'Uploading attendance sheet ${i + 1} to: $_attendanceBucket/$key',
        );

        final success = await S3TransferHelper.upload(
          bucket: _attendanceBucket,
          key: key,
          body: encryptedBytes,
          contentType: 'image/png',
        );

        if (success) {
          successCount++;
        } else {
          errors.add("Failed to upload image ${i + 1}");
        }
      }

      if (successCount == imagePaths.length) {
        return {
          'success': true,
          'message': '$successCount attendance sheet(s) uploaded successfully.',
          'count': successCount,
        };
      } else if (successCount > 0) {
        return {
          'success': true, // Partial success
          'message':
              'Uploaded $successCount/${imagePaths.length} sheets. Errors: ${errors.join(", ")}',
          'count': successCount,
        };
      } else {
        return {
          'success': false,
          'error':
              'Upload failed. Please check your internet connection and try again.',
          'details': errors.join(", "),
        };
      }
    } catch (e) {
      debugPrint('Error in uploadAttendanceSheetImages: $e');
      return {'success': false, 'error': 'Upload failed. Please try again.'};
    }
  }
}
