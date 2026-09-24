import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/security/image_encryption_service.dart';
import 's3_transfer_helper.dart';

/// Handles assembling incident / malpractice PDF reports and uploading evidence photos to S3.
class IncidentUploadService {
  static const String _bucketName = 'bits-supervisorapp';

  /// Upload Incident Report (JSON, Photos, and A4 PDF) to S3
  /// S3 Structure: bits-supervisorapp/Incident-Reports/{SupervisorID}/{Date}/{StudentID}_*
  static Future<Map<String, dynamic>> uploadIncidentReport({
    required Map<String, dynamic> formData,
    required List<String> photosPaths,
  }) async {
    try {
      // 1. Get Supervisor ID from local cache
      final prefs = SharedPreferencesAsync();
      final supervisorId =
          await prefs.getString('current_supervisor_id') ?? 'unknown_supervisor';

      // 2. Format Date (YYYY-MM-DD)
      final now = DateTime.now();
      final dateStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      final studentId = formData['studentId'] ?? 'unknown';
      const targetBucket = _bucketName;

      debugPrint('Starting incident report upload for $studentId by $supervisorId');

      // 3. Upload JSON data
      final jsonKey =
          "Incident-Reports/$supervisorId/$dateStr/${studentId}_incident.json";
      final jsonData = {
        ...formData,
        'supervisorId': supervisorId,
        'timestamp': now.toIso8601String(),
        'date': dateStr,
      };

      final jsonBytes = utf8.encode(json.encode(jsonData));

      debugPrint('Uploading JSON to: $targetBucket/$jsonKey');
      final jsonUploadSuccess = await S3TransferHelper.upload(
        bucket: targetBucket,
        key: jsonKey,
        body: jsonBytes,
        contentType: 'application/json',
      );

      if (!jsonUploadSuccess) {
        throw Exception('Failed to upload incident report JSON.');
      }
      debugPrint('Incident JSON uploaded successfully');

      // 4. Upload evidence photos
      int photoCount = 0;
      for (int i = 0; i < photosPaths.length; i++) {
        final photoPath = photosPaths[i];
        final photoFile = File(photoPath);

        if (await photoFile.exists()) {
          final photoBytes = await photoFile.readAsBytes();
          final encryptedBytes =
              await ImageEncryptionService.encryptImageBytes(photoBytes);
          final photoKey =
              "Incident-Reports/$supervisorId/$dateStr/${studentId}_photos/photo_${i + 1}.jpg";

          debugPrint('Uploading photo ${i + 1} to: $targetBucket/$photoKey');
          final photoUploadSuccess = await S3TransferHelper.upload(
            bucket: targetBucket,
            key: photoKey,
            body: encryptedBytes,
            contentType: 'image/jpeg',
          );

          if (photoUploadSuccess) {
            photoCount++;
            debugPrint(' Photo ${i + 1} uploaded successfully');
          } else {
            debugPrint(' Failed to upload photo ${i + 1}');
          }
        }
      }

      // 5. Generate PDF report
      final pdf = pw.Document();

      // Incident summary page
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'INCIDENT REPORT',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.SizedBox(height: 20),
                pw.Text(
                  'STUDENT INFORMATION',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Student ID: ${formData['studentId']}'),
                pw.Text('Student Name: ${formData['studentName']}'),
                pw.Text('Course Code: ${formData['courseCode']}'),
                pw.Text('Course Name: ${formData['courseName']}'),
                pw.SizedBox(height: 20),
                pw.Text(
                  'LOCATION INFORMATION',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text('City: ${formData['cityName']}'),
                pw.Text('Centre: ${formData['centreName']}'),
                pw.Text(
                  'GPS: Lat ${formData['latitude'] ?? 'N/A'} & Long ${formData['longitude'] ?? 'N/A'}',
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'INCIDENT DETAILS',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Nature of UFM: ${formData['ufm']}'),
                pw.Text('Type of Offence: ${formData['offence']}'),
                if (formData['offenceDetails'] != null &&
                    formData['offenceDetails'].toString().isNotEmpty)
                  pw.Text('Offence Details: ${formData['offenceDetails']}'),
                pw.SizedBox(height: 20),
                pw.Text(
                  'DESCRIPTION',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(formData['description'] ?? ''),
                pw.SizedBox(height: 20),
                pw.Text(
                  'REPORT INFORMATION',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Supervisor ID: $supervisorId'),
                pw.Text('Date: $dateStr'),
                pw.Text('Time: ${DateFormat('HH:mm:ss').format(now)}'),
                pw.Text('Photos Captured: $photoCount'),
              ],
            );
          },
        ),
      );

      // Add each photo as a dedicated page in the PDF
      for (int i = 0; i < photosPaths.length; i++) {
        final photoFile = File(photosPaths[i]);
        if (await photoFile.exists() && await photoFile.length() > 0) {
          final photoBytes = await photoFile.readAsBytes();
          if (photoBytes.isEmpty) continue;
          final image = pw.MemoryImage(photoBytes);
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context context) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Photo ${i + 1}',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Expanded(
                      child: pw.Center(
                        child: pw.Image(image, fit: pw.BoxFit.contain),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        }
      }

      final pdfBytes = await pdf.save();
      if (pdfBytes.isEmpty) {
        throw Exception('Generated incident PDF buffer is empty (0 bytes)');
      }
      debugPrint('Incident PDF created, size: ${pdfBytes.length} bytes');

      // 6. Upload PDF to S3
      final pdfKey =
          "Incident-Reports/$supervisorId/$dateStr/${studentId}_report.pdf";
      debugPrint('Uploading Incident PDF to: $targetBucket/$pdfKey');

      final pdfUploadSuccess = await S3TransferHelper.upload(
        bucket: targetBucket,
        key: pdfKey,
        body: pdfBytes,
        contentType: 'application/pdf',
      );

      if (!pdfUploadSuccess) {
        throw Exception('Failed to upload incident PDF report.');
      }
      debugPrint(' Incident PDF uploaded successfully');

      return {
        'success': true,
        'message': 'Incident report uploaded successfully.',
        'photosUploaded': photoCount,
        'totalPhotos': photosPaths.length,
      };
    } catch (e) {
      debugPrint('Error in uploadIncidentReport: $e');
      return {
        'success': false,
        'error': 'Failed to submit report. Please try again.',
      };
    }
  }
}
