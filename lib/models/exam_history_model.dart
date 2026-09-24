import 'package:intl/intl.dart';

class ExamHistoryModel {
  final String key;
  final String studentId;
  final String courseCode;
  final String slot;
  final DateTime examDate;
  final int? pageCount;
  final String status;

  ExamHistoryModel({
    required this.key,
    required this.studentId,
    required this.courseCode,
    required this.slot,
    required this.examDate,
    this.pageCount,
    this.status = 'Success',
  });

  String get formattedDate => DateFormat('dd-MM-yyyy').format(examDate);
  String get formattedTime => DateFormat('hh:mm a').format(examDate);

  String get displayName {
    if (slot.toLowerCase() == 'frontpage' || slot == '0') {
      return 'Front Page';
    }
    return 'Question - $slot';
  }

  int get questionNumber {
    if (slot.toLowerCase() == 'frontpage') return 0;
    final num = int.tryParse(slot.replaceAll(RegExp(r'[^0-9]'), ''));
    return num ?? -1;
  }

  ExamHistoryModel copyWith({
    String? key,
    String? studentId,
    String? courseCode,
    String? slot,
    DateTime? examDate,
    int? pageCount,
    String? status,
  }) {
    return ExamHistoryModel(
      key: key ?? this.key,
      studentId: studentId ?? this.studentId,
      courseCode: courseCode ?? this.courseCode,
      slot: slot ?? this.slot,
      examDate: examDate ?? this.examDate,
      pageCount: pageCount ?? this.pageCount,
      status: status ?? this.status,
    );
  }
}
