import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/s3_uploader.dart';

/// Handles assembling student answer sheet images into PDF documents
/// and uploading them to S3 via pre-signed URLs.
/// Includes the Question Header cover page and per-page headers matching the Exam App design.
class AnswerSheetUploadService {
  /// Compress image for PDF to reduce file size and processing time
  static Future<Uint8List> _compressImageForPDF(Uint8List imageBytes) async {
    return await compute(_compressImageIsolate, imageBytes);
  }

  /// Isolate function for image compression
  static Uint8List _compressImageIsolate(Uint8List imageBytes) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return imageBytes;

      // Resize to max 2000px width while maintaining aspect ratio (for PDF clarity)
      const maxWidth = 2000;
      const maxHeight = 2800; // A4 aspect ratio

      int newWidth = image.width;
      int newHeight = image.height;

      if (image.width > maxWidth) {
        newWidth = maxWidth;
        newHeight = (image.height * maxWidth / image.width).round();
      }

      if (newHeight > maxHeight) {
        newHeight = maxHeight;
        newWidth = (image.width * maxHeight / image.height).round();
      }

      // Only resize if needed
      final resizedImage =
          (newWidth != image.width || newHeight != image.height)
          ? img.copyResize(
              image,
              width: newWidth,
              height: newHeight,
              interpolation: img.Interpolation.linear,
            )
          : image;

      // Compress to JPEG with quality optimized for documents
      return img.encodeJpg(resizedImage, quality: 80);
    } catch (e) {
      debugPrint('Image compression failed: $e');
      return imageBytes; // Return original if compression fails
    }
  }

  /// Upload Answer Sheets to S3
  /// S3 Key Structure: Exam-answers/{studentId}/{Date}/{CourseCode}/question-{Slot}.pdf
  static Future<Map<String, dynamic>> uploadAnswerSheets({
    required String studentId,
    String? studentName,
    required String courseCode,
    required Map<String, List<String>>
    capturedImages, // Key: Q1, Value: List of paths
  }) async {
    try {
      final prefs = SharedPreferencesAsync();
      final supervisorId =
          await prefs.getString('current_supervisor_id') ??
          'unknown_supervisor';

      final now = DateTime.now();
      final dateStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      int successCount = 0;
      List<String> errors = [];

      debugPrint(
        ' [AnswerSheetUpload] Uploading for $courseCode by $supervisorId (Student: $studentId)',
      );

      for (var entry in capturedImages.entries) {
        final slot = entry.key; // e.g., "Q1"
        final imagePaths = entry.value;

        if (imagePaths.isEmpty) continue;

        try {
          debugPrint(
            ' [AnswerSheetUpload] Building PDF for $slot (${imagePaths.length} pages)...',
          );

          final pdf = pw.Document();
          final isFrontPage = slot
              .toLowerCase()
              .replaceAll(' ', '')
              .contains('front');
          final String questionTitle;
          if (isFrontPage) {
            questionTitle = 'Front Page';
          } else {
            final upper = slot.trim().toUpperCase();
            questionTitle = upper.startsWith('Q') ? upper : 'Q$upper';
          }

          // 1. Add Question Header Cover Page (matching Exam App design)
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(40),
              build: (pw.Context context) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Question Header Card
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(20),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.blue50,
                        border: pw.Border.all(
                          color: PdfColors.blue300,
                          width: 2,
                        ),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(8),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            questionTitle,
                            style: pw.TextStyle(
                              fontSize: 24,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue800,
                            ),
                          ),
                          pw.SizedBox(height: 10),
                          pw.Text('Question ID: $questionTitle'),
                          if (studentName != null && studentName.isNotEmpty)
                            pw.Text(
                              'Student: $studentName ($studentId@wilp.bits-pilani.ac.in)',
                            )
                          else
                            pw.Text('Student: $studentId'),
                          pw.Text('Course: $courseCode'),
                          pw.Text('Images: ${imagePaths.length}'),
                          pw.Text(
                            supervisorId != 'unknown_supervisor'
                                ? 'Submitted By: Supervisor ($supervisorId)'
                                : 'Submitted By: Supervisor',
                          ),
                          pw.Text(
                            'Generated: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(now)}',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );

          // 2. Add Image Pages with Header Banner (matching Exam App design)
          int addedImagesCount = 0;
          for (int i = 0; i < imagePaths.length; i++) {
            final imageFile = File(imagePaths[i]);
            if (await imageFile.exists() && await imageFile.length() > 0) {
              final imageBytes = await imageFile.readAsBytes();
              if (imageBytes.isEmpty) {
                debugPrint(
                  '⚠️ [PDF] Read 0 bytes from image: ${imagePaths[i]}',
                );
                continue;
              }

              final compressedBytes = await _compressImageForPDF(imageBytes);
              final bytesToUse = compressedBytes.isNotEmpty
                  ? compressedBytes
                  : imageBytes;
              final image = pw.MemoryImage(bytesToUse);

              pdf.addPage(
                pw.Page(
                  pageFormat: PdfPageFormat.a4,
                  margin: const pw.EdgeInsets.all(20),
                  build: (pw.Context context) {
                    return pw.Column(
                      children: [
                        // Header banner
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.all(12),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.blue50,
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                color: PdfColors.blue200,
                                width: 2,
                              ),
                            ),
                          ),
                          child: pw.Text(
                            '$questionTitle - Page ${i + 1} of ${imagePaths.length}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.SizedBox(height: 10),
                        // Image
                        pw.Expanded(
                          child: pw.Image(image, fit: pw.BoxFit.contain),
                        ),
                      ],
                    );
                  },
                ),
              );
              addedImagesCount++;
            } else {
              debugPrint(
                '⚠️ [PDF] Image file does not exist on disk or is 0 bytes: ${imagePaths[i]}',
              );
            }
          }

          if (addedImagesCount == 0 && imagePaths.isNotEmpty) {
            throw Exception(
              'All ${imagePaths.length} expected images were missing or empty on disk for $slot!',
            );
          }

          final pdfBytes = await pdf.save();
          if (pdfBytes.isEmpty) {
            throw Exception(
              'Generated PDF buffer is empty (0 bytes) for $slot',
            );
          }
          debugPrint(
            ' [AnswerSheetUpload] PDF generated for $slot (${pdfBytes.length} bytes)',
          );

          // Upload via Pre-signed URL
          final effectivePageCount = imagePaths.isNotEmpty
              ? imagePaths.length
              : 1;
          final uploadResult = await S3Uploader.requestUrlAndUpload(
            uploadType: 'answer_sheet',
            metadata: {
              'studentId': studentId.toLowerCase(),
              'date': dateStr,
              'courseCode': courseCode,
              'slot': isFrontPage ? 'FrontPage' : questionTitle,
              'pageCount': effectivePageCount,
              'pages': effectivePageCount.toString(),
              's3Metadata': {'pages': effectivePageCount.toString()},
            },
            bytes: pdfBytes,
            contentType: 'application/pdf',
          );

          if (uploadResult['success'] != true) {
            throw Exception(uploadResult['error'] ?? 'S3 Upload failed');
          }

          debugPrint(' [AnswerSheetUpload] Successfully uploaded $slot');
          successCount++;
        } catch (e) {
          debugPrint(' [AnswerSheetUpload] Error uploading slot $slot: $e');
          errors.add("Slot $slot: $e");
        }
      }

      if (successCount == 0 && capturedImages.isNotEmpty) {
        return {
          'success': false,
          'error':
              'Failed to upload answer sheets. Please check your internet connection and try again.',
        };
      }

      return {
        'success': true,
        'count': successCount,
        'message': 'Successfully uploaded $successCount answer sheets.',
        'errors': errors,
      };
    } catch (e) {
      debugPrint(' [AnswerSheetUpload] Unexpected error: $e');
      return {
        'success': false,
        'error': 'Upload failed. Please try again or contact support.',
      };
    }
  }
}
