import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supervisorapp/constants/app_constants.dart';
import '../storage/s3_transfer_helper.dart';

/// Service to log answer sheet uploads to S3 as CSV.
/// S3 Location: bits-supervisorapp/answerupload-logs/upload_log.csv
class AnswerUploadLogService {
  static const String _bucketName = 'bits-supervisorapp';
  static const String _logFolder = 'answerupload-logs';
  static const String _logFileName = 'upload_log.csv';

  /// Log an answer sheet upload event
  static Future<bool> logUpload({
    required String supervisorId,
    required String studentId,
    required String courseCode,
    required String courseName,
    required String questionNo,
    String appVersion = AppConstants.appVersion,
  }) async {
    try {
      final now = DateTime.now();
      final uploadDate = DateFormat('dd-MM-yyyy').format(now);
      final uploadTime = DateFormat('HH:mm:ss').format(now);

      final csvRow = _createCsvRow(
        supervisorId: supervisorId,
        studentId: studentId,
        courseCode: courseCode,
        courseName: courseName,
        questionNo: questionNo,
        uploadDate: uploadDate,
        uploadTime: uploadTime,
        appVersion: appVersion,
      );

      debugPrint(' Logging upload: $csvRow');

      final existingContent = await _downloadLogFile();
      final updatedContent = '$existingContent$csvRow\n';

      final success = await _uploadLogFile(updatedContent);

      if (success) {
        debugPrint(' Upload logged successfully');
      } else {
        debugPrint(' Failed to log upload');
      }

      return success;
    } catch (e) {
      debugPrint(' Error logging upload: $e');
      return false;
    }
  }

  static String _createCsvRow({
    required String supervisorId,
    required String studentId,
    required String courseCode,
    required String courseName,
    required String questionNo,
    required String uploadDate,
    required String uploadTime,
    String appVersion = AppConstants.appVersion,
  }) {
    String escapeField(String field) {
      if (field.contains(',') || field.contains('"') || field.contains('\n')) {
        return '"${field.replaceAll('"', '""')}"';
      }
      return field;
    }

    return [
      escapeField(supervisorId),
      escapeField(studentId),
      escapeField(courseCode),
      escapeField(courseName),
      escapeField(questionNo),
      escapeField(uploadDate),
      escapeField(uploadTime),
      escapeField(appVersion),
    ].join(',');
  }

  static Future<String> _downloadLogFile() async {
    const defaultHeader =
        'Supervisor ID,Student ID,Course Code,Course Name,Question No,Upload Date,Upload Time,App Version\n';
    try {
      final key = '$_logFolder/$_logFileName';
      final bytes = await S3TransferHelper.download(
        bucket: _bucketName,
        key: key,
      );
      if (bytes != null && bytes.isNotEmpty) {
        var content = utf8.decode(bytes);
        if (content.startsWith('Supervisor ID') &&
            !content.split('\n').first.contains('App Version')) {
          final firstNewline = content.indexOf('\n');
          if (firstNewline != -1) {
            content = defaultHeader + content.substring(firstNewline + 1);
          }
        }
        return content;
      }
      return defaultHeader;
    } catch (e) {
      debugPrint(' Error downloading log file: $e');
      return defaultHeader;
    }
  }

  static Future<bool> _uploadLogFile(String content) async {
    try {
      final key = '$_logFolder/$_logFileName';
      return await S3TransferHelper.upload(
        bucket: _bucketName,
        key: key,
        body: utf8.encode(content),
        contentType: 'text/csv',
      );
    } catch (e) {
      debugPrint(' Error uploading log file: $e');
      return false;
    }
  }
}

/// Backward compatibility alias
typedef UploadLogService = AnswerUploadLogService;
