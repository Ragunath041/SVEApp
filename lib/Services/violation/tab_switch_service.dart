import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_client.dart';
import 'package:supervisorapp/Services/ExamDetailsService.dart';

/// Handles tab-switch violation monitoring and timeout count detection for students.
class TabSwitchService {
  TabSwitchService();

  /// Fetches timeout logs for a specific student or centre.
  Future<List<Map<String, String>>> fetchTimeoutLogs({
    String? studentId,
    List<String>? studentIds,
    String? centre,
    List<Map<String, dynamic>>? activeExams,
    String rootPrefix = 'tabswitch_violation/',
    String? date,
    String? courseCode,
  }) async {
    List<Map<String, String>> logs = [];

    try {
      debugPrint(' [TabSwitchService] Starting fetch from backend for $centre / $studentId');

      List<String> targetStudentIds = [];

      if (studentId != null && studentId.isNotEmpty) {
        targetStudentIds = [studentId.trim().toLowerCase()];
      } else if (studentIds != null && studentIds.isNotEmpty) {
        targetStudentIds = studentIds.map((id) => id.trim().toLowerCase()).toList();
      } else if (centre != null && centre.isNotEmpty) {
        final studentsInCenter =
            await ExamDetailsService.getStudentIdsInCentreForActiveExam(
              centre,
              activeExams ?? [],
            );
        targetStudentIds = studentsInCenter.map((id) => id.trim().toLowerCase()).toList();
      }

      final response = await ApiClient.sendAction(
        action: 'getTabSwitchViolations',
        payload: {
          'studentIds': targetStudentIds,
          if (studentId != null && studentId.isNotEmpty) 'studentId': studentId.trim().toLowerCase(),
          'rootPrefix': rootPrefix,
          if (date != null && date.isNotEmpty) 'date': date,
          if (courseCode != null && courseCode.isNotEmpty) 'courseCode': courseCode,
        },
      );

      if (response['success'] == true && response['logs'] != null) {
        final rawLogs = response['logs'] as List;
        for (var item in rawLogs) {
          if (item is Map) {
            logs.add(item.map((k, v) => MapEntry(k.toString(), v.toString())));
          }
        }
      }

      debugPrint(' [TabSwitchService] Retrieved ${logs.length} timeout logs');
      return logs;
    } catch (e) {
      debugPrint(' [TabSwitchService] Error fetching timeout logs: $e');
      return logs;
    }
  }

  /// Fast server-side violation counter for the active session
  Future<int> countViolationsForActiveSession({
    required String centre,
    required List<Map<String, dynamic>> activeExams,
  }) async {
    if (activeExams.isEmpty) return 0;

    try {
      final studentIdsInCenter =
          await ExamDetailsService.getStudentIdsInCentreForActiveExam(
            centre,
            activeExams,
          );

      if (studentIdsInCenter.isEmpty) return 0;

      final todayYMD = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final todayDMY = DateFormat('dd-MM-yyyy').format(DateTime.now());

      final response = await ApiClient.sendAction(
        action: 'countViolations',
        payload: {
          'studentIds': studentIdsInCenter.map((id) => id.trim().toLowerCase()).toList(),
          'dates': [todayYMD, todayDMY],
        },
      );

      if (response['success'] == true && response['count'] != null) {
        final count = (response['count'] as num).toInt();
        debugPrint(' [TabSwitchService] Violations count for $centre: $count');
        return count;
      }
      return 0;
    } catch (e) {
      debugPrint(' [TabSwitchService] Error counting violations: $e');
      return 0;
    }
  }

  void dispose() {}
}

/// Backward compatibility alias
typedef S3TimeoutService = TabSwitchService;
