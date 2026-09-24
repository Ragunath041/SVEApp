import 'package:flutter/foundation.dart';
import '../../models/exam_history_model.dart';
import '../../core/network/api_client.dart';

/// Fetches submitted answer sheet history and page counts for a student.
class StudentExamHistoryService {
  StudentExamHistoryService();

  /// Lists all exam history for a specific student ID via backend API
  Future<List<ExamHistoryModel>> fetchStudentExamHistory(
    String studentId,
  ) async {
    List<ExamHistoryModel> exams = [];
    try {
      debugPrint(' [StudentExamHistoryService] Fetching history for $studentId');

      final response = await ApiClient.sendAction(
        action: 'getStudentExamHistory',
        payload: {
          'studentId': studentId.trim().toLowerCase(),
        },
      );

      if (response['success'] == true && response['exams'] != null) {
        final List rawExams = response['exams'] as List;

        for (var obj in rawExams) {
          if (obj is Map) {
            DateTime examDate = DateTime.now();
            final lastModifiedStr = obj['lastModified']?.toString();
            final dateStr = obj['examDate']?.toString();

            if (lastModifiedStr != null) {
              examDate = DateTime.tryParse(lastModifiedStr)?.toLocal() ?? examDate;
            }
            if (dateStr != null) {
              try {
                final pathDate = DateTime.parse(dateStr);
                examDate = DateTime(
                  pathDate.year,
                  pathDate.month,
                  pathDate.day,
                  examDate.hour,
                  examDate.minute,
                  examDate.second,
                );
              } catch (_) {}
            }

            exams.add(
              ExamHistoryModel(
                key: (obj['key'] ?? '').toString(),
                studentId: (obj['studentId'] ?? studentId).toString(),
                courseCode: (obj['courseCode'] ?? '').toString(),
                slot: (obj['slot'] ?? '').toString(),
                examDate: examDate,
                pageCount: (obj['pageCount'] as num?)?.toInt(),
                status: 'Success',
              ),
            );
          }
        }
      }

      // Sort by date descending
      exams.sort((a, b) => b.examDate.compareTo(a.examDate));
      return exams;
    } catch (e) {
      debugPrint(' [StudentExamHistoryService] Error fetching history: $e');
      return exams;
    }
  }

  /// Fetches detailed info for exams (page count is already fetched server-side)
  Future<List<ExamHistoryModel>> fetchDetails(
    List<ExamHistoryModel> exams,
  ) async {
    return exams;
  }

  void dispose() {}
}

/// Backward compatibility alias
typedef S3ExamHistoryService = StudentExamHistoryService;
