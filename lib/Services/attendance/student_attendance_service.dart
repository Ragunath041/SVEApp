import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_client.dart';

/// Handles student exam attendance recording, pending questions decrement,
/// incident marking, and session attendance lookups.
class StudentAttendanceService {
  /// Save student login/attendance record via backend API
  static Future<bool> saveLoginRecord({
    required String bitsId,
    required double latitude,
    required double longitude,
    required DateTime loginTime,
    required int noOfQuestionsPending,
    required String courseCode,
    required String examDate,
    required String examStartTime,
    required String examEndTime,
    required String sessionType,
    required String center,
    String? uploadStartTime,
  }) async {
    try {
      debugPrint(' [StudentAttendanceService] Saving student attendance for $bitsId');

      final attendanceId =
          '${bitsId.toLowerCase()}_${loginTime.millisecondsSinceEpoch}';

      final response = await ApiClient.sendAction(
        action: 'saveStudentAttendance',
        payload: {
          'bitsId': bitsId.trim().toLowerCase(),
          'attendanceId': attendanceId,
          'loginDate': DateFormat('yyyy-MM-dd').format(loginTime),
          'loginTime': DateFormat('HH:mm:ss').format(loginTime),
          'latitude': latitude,
          'longitude': longitude,
          'timestamp': loginTime.millisecondsSinceEpoch,
          'finished': '00:00:00',
          'noOfQuestionsPending': noOfQuestionsPending,
          'courseCode': courseCode.toUpperCase().replaceAll(' ', ''),
          'examDate': examDate.trim(),
          'examStartTime': _formatTimeForDB(examStartTime),
          'examEndTime': _formatTimeForDB(examEndTime),
          'sessionType': sessionType.trim().toUpperCase(),
          'center': center.trim(),
          'uploadStartTime':
              uploadStartTime ?? DateFormat('HH:mm:ss').format(loginTime),
        },
      );

      final success = response['success'] == true;
      if (success) {
        debugPrint(' [StudentAttendanceService] Student attendance saved successfully');
      } else {
        debugPrint(' [StudentAttendanceService] Save failed: ${response['error']}');
      }
      return success;
    } catch (e) {
      debugPrint(' [StudentAttendanceService] Exception saving student attendance: $e');
      return false;
    }
  }

  /// Update finished time when exam is completed
  static Future<bool> updateFinishedTime({
    required String bitsId,
    required String attendanceId,
    required DateTime finishedTime,
  }) async {
    try {
      final finishStr = DateFormat('HH:mm:ss').format(finishedTime);
      debugPrint(' [StudentAttendanceService] Updating finished time for $bitsId to $finishStr');

      final response = await ApiClient.sendAction(
        action: 'updateFinishedTime',
        payload: {
          'bitsId': bitsId.trim().toLowerCase(),
          'attendanceId': attendanceId.trim(),
          'finishedTime': finishStr,
        },
      );

      return response['success'] == true;
    } catch (e) {
      debugPrint(' [StudentAttendanceService] Exception updating finished time: $e');
      return false;
    }
  }

  /// Mark the finished column as '99:99:99' for incident reports
  static Future<bool> markAsIncident({
    required String bitsId,
    required String courseCode,
    required String examDate,
    String? session,
  }) async {
    try {
      debugPrint(
        ' [StudentAttendanceService] Marking incident for student $bitsId ($courseCode)',
      );

      final response = await ApiClient.sendAction(
        action: 'markIncidentAttendance',
        payload: {
          'bitsId': bitsId.trim().toLowerCase(),
          'courseCode': courseCode.trim().toUpperCase().replaceAll(' ', ''),
          'examDate': examDate.trim(),
          if (session != null && session.isNotEmpty) 'session': session.trim().toUpperCase(),
        },
      );

      return response['success'] == true;
    } catch (e) {
      debugPrint(' [StudentAttendanceService] Exception in markAsIncident: $e');
      return false;
    }
  }

  /// Decrement noOfQuestionsPending by 1 when a question is uploaded
  static Future<bool> decrementNoOfQuestionsPending({
    required String bitsId,
    required String attendanceId,
  }) async {
    try {
      debugPrint(' [StudentAttendanceService] Decrementing pending questions for $bitsId');

      final response = await ApiClient.sendAction(
        action: 'decrementQuestionsPending',
        payload: {
          'bitsId': bitsId.trim().toLowerCase(),
          'attendanceId': attendanceId.trim(),
        },
      );

      return response['success'] == true;
    } catch (e) {
      debugPrint(' [StudentAttendanceService] Exception decrementing questions: $e');
      return false;
    }
  }

  /// Check if attendance already exists for this exam session
  static Future<String?> getExistingAttendance({
    required String bitsId,
    required String courseCode,
    required String examDate,
    String? sessionType,
  }) async {
    try {
      final response = await ApiClient.sendAction(
        action: 'getExistingAttendance',
        payload: {
          'bitsId': bitsId.trim().toLowerCase(),
          'courseCode': courseCode.trim().toUpperCase().replaceAll(' ', ''),
          'examDate': examDate.trim(),
          if (sessionType != null && sessionType.isNotEmpty)
            'sessionType': sessionType.trim().toUpperCase(),
        },
      );

      if (response['success'] == true && response['attendanceId'] != null) {
        return response['attendanceId'].toString();
      }
      return null;
    } catch (e) {
      debugPrint(' [StudentAttendanceService] Exception checking existing attendance: $e');
      return null;
    }
  }

  /// Get student's attendance record from database
  static Future<Map<String, dynamic>?> getAttendanceRecord({
    required String bitsId,
    required String courseCode,
    required String examDate,
    String? sessionType,
  }) async {
    try {
      final response = await ApiClient.sendAction(
        action: 'getExistingAttendance',
        payload: {
          'bitsId': bitsId.trim().toLowerCase(),
          'courseCode': courseCode.trim().toUpperCase().replaceAll(' ', ''),
          'examDate': examDate.trim(),
          if (sessionType != null && sessionType.isNotEmpty)
            'sessionType': sessionType.trim().toUpperCase(),
        },
      );

      if (response['success'] == true && response['data'] != null) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
      return null;
    } catch (e) {
      debugPrint(' [StudentAttendanceService] Exception getting attendance record: $e');
      return null;
    }
  }

  static String _formatTimeForDB(String time) {
    time = time.trim();
    if (time.isEmpty) return "00:00:00";
    final parts = time.split(':');
    if (parts.length == 2) {
      return "${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}:00";
    }
    if (parts.length == 3) {
      return "${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}:${parts[2].padLeft(2, '0')}";
    }
    return time;
  }
}

/// Backward compatibility alias
typedef DynamoDBAttendanceService = StudentAttendanceService;
