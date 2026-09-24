import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supervisorapp/constants/app_constants.dart';
import '../storage/s3_transfer_helper.dart';

/// Handles recording supervisor audit trails to a single unified S3 CSV log.
/// S3 Target: s3://bitswilp-data/Supervisorapp_logs/logs.csv
class SupervisorAuditLogService {
  static const String _bucketName = 'bitswilp-data';
  static const String _folder = 'Supervisorapp_logs';
  static const String _logFileName = 'logs.csv';

  static const String _csvHeader =
      'date,time,log_type,supervisor_id,action,status,centre,exam_date,session,latitude,longitude,face_score,os_type,app_version,error_message\n';

  static String _escapeField(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// Core unified log method that writes to S3://bitswilp-data/Supervisorapp_logs/logs.csv
  static Future<void> log({
    required String logType,
    required String supervisorId,
    required String action,
    required String status,
    String centre = '',
    String examDate = '',
    String session = '',
    String latitude = '',
    String longitude = '',
    String faceScore = '',
    String appVersion = AppConstants.appVersion,
    String errorMessage = '',
  }) async {
    // Ignore LOGOUT events as per user requirement
    if (action.toUpperCase() == 'LOGOUT') {
      return;
    }

    try {
      final now = DateTime.now();
      final dateStr = DateFormat('dd-MM-yyyy').format(now);
      final timeStr = DateFormat('HH:mm:ss').format(now);
      final osType = Platform.isAndroid
          ? 'Android'
          : (Platform.isIOS ? 'iOS' : Platform.operatingSystem);

      final row = [
        dateStr,
        timeStr,
        logType,
        supervisorId,
        action,
        status,
        centre,
        examDate,
        session,
        latitude,
        longitude,
        faceScore,
        osType,
        appVersion,
        errorMessage,
      ].map((f) => _escapeField(f)).join(',');

      final key = '$_folder/$_logFileName';
      String existingContent = '';

      final bytes = await S3TransferHelper.download(
        bucket: _bucketName,
        key: key,
      );

      if (bytes != null && bytes.isNotEmpty) {
        existingContent = utf8.decode(bytes);
        // Automatically upgrade existing header if it is missing app_version
        if (existingContent.startsWith('date,time,log_type') &&
            !existingContent.split('\n').first.contains('app_version')) {
          final firstNewline = existingContent.indexOf('\n');
          if (firstNewline != -1) {
            existingContent =
                _csvHeader + existingContent.substring(firstNewline + 1);
          }
        }
        if (!existingContent.endsWith('\n')) {
          existingContent += '\n';
        }
      } else {
        existingContent = _csvHeader;
      }

      final updatedContent = '$existingContent$row\n';
      await S3TransferHelper.upload(
        bucket: _bucketName,
        key: key,
        body: utf8.encode(updatedContent),
        contentType: 'text/csv',
      );
      debugPrint(
        ' [SupervisorAuditLog] Logged $action ($status, $appVersion) to $key',
      );
    } catch (e) {
      debugPrint(' [SupervisorAuditLog] Error logging to $_logFileName: $e');
    }
  }

  /// Log registration activity (delegates to unified log)
  static Future<void> logRegistration({
    required String supervisorId,
    required String action,
    String details = '',
    required String status,
    String errorMessage = '',
    String faceSimilarity = '',
    String centre = '',
    String latitude = '',
    String longitude = '',
    String appVersion = AppConstants.appVersion,
  }) async {
    await log(
      logType: 'REGISTRATION',
      supervisorId: supervisorId,
      action: action,
      status: status,
      centre: centre,
      latitude: latitude,
      longitude: longitude,
      faceScore: faceSimilarity,
      appVersion: appVersion,
      errorMessage: errorMessage,
    );
  }

  /// Log attendance/login activity (delegates to unified log)
  static Future<void> logAttendance({
    required String supervisorId,
    required String action,
    required String status,
    String errorMessage = '',
    String examDate = '',
    String session = '',
    String gpsLatitude = '',
    String gpsLongitude = '',
    String verificationScore = '',
    String centre = '',
    String appVersion = AppConstants.appVersion,
  }) async {
    await log(
      logType: 'ATTENDANCE',
      supervisorId: supervisorId,
      action: action,
      status: status,
      centre: centre,
      examDate: examDate,
      session: session,
      latitude: gpsLatitude,
      longitude: gpsLongitude,
      faceScore: verificationScore,
      appVersion: appVersion,
      errorMessage: errorMessage,
    );
  }
}

/// Backward compatibility alias
typedef S3LogService = SupervisorAuditLogService;
