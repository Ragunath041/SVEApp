import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_client.dart';

/// Tracks student exam progress per question slot (Q1-Q15),
/// initializing slots and updating page counts / upload timestamps.
class ExamProgressService {
  /// Create initial record with all 15 questions set to "0" without overwriting existing questions
  static Future<bool> createInitialRecord({
    required String bitsId,
    required String attendanceId,
    required String courseCode,
    required String examDate,
    required String sessionType,
  }) async {
    try {
      debugPrint(
        ' [ExamProgressService] Initializing record for $bitsId (Attendance: $attendanceId)',
      );

      final response = await ApiClient.sendAction(
        action: 'initFinishedRecord',
        payload: {
          'bitsId': bitsId.trim().toLowerCase(),
          'attendanceId': attendanceId.trim(),
          'courseCode': courseCode.trim().toUpperCase().replaceAll(' ', ''),
          'examDate': examDate.trim(),
          'sessionType': sessionType.trim().toUpperCase(),
        },
      );

      final success = response['success'] == true;
      if (success) {
        debugPrint(' [ExamProgressService] Record initialized successfully');
      } else {
        debugPrint(' [ExamProgressService] Init failed: ${response['error']}');
      }
      return success;
    } catch (e) {
      debugPrint(' [ExamProgressService] Error creating finished record: $e');
      return false;
    }
  }

  /// Update specific question timestamp or page count when uploaded
  static Future<bool> updateQuestionTimestamp({
    required String bitsId,
    required String attendanceId,
    required int questionNumber, // 1 to 15
    required DateTime uploadTime,
    int? pageCount,
  }) async {
    try {
      if (questionNumber < 1 || questionNumber > 15) {
        debugPrint(
          ' [ExamProgressService] Invalid question number: $questionNumber',
        );
        return false;
      }

      final displayValue = pageCount != null
          ? pageCount.toString()
          : DateFormat('HH:mm:ss').format(uploadTime);

      debugPrint(
        ' [ExamProgressService] Updating question $questionNumber to $displayValue for $bitsId',
      );

      final response = await ApiClient.sendAction(
        action: 'updateFinishedQuestion',
        payload: {
          'bitsId': bitsId.trim().toLowerCase(),
          'attendanceId': attendanceId.trim(),
          'questionNumber': questionNumber,
          'value': displayValue,
        },
      );

      final success = response['success'] == true;
      if (success) {
        debugPrint(
          ' [ExamProgressService] Question $questionNumber updated successfully',
        );
      } else {
        debugPrint(
          ' [ExamProgressService] Update failed: ${response['error']}',
        );
      }
      return success;
    } catch (e) {
      debugPrint(
        ' [ExamProgressService] Error updating question timestamp: $e',
      );
      return false;
    }
  }
}

/// Backward compatibility alias
typedef DynamoDBFinishedService = ExamProgressService;
