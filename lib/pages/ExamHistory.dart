import 'package:flutter/material.dart';
import 'package:supervisorapp/Services/exam/student_exam_history_service.dart';
import '../models/exam_history_model.dart';

class ExamHistoryPage extends StatefulWidget {
  final String studentId;
  final Map<String, String> examDetails;

  const ExamHistoryPage({
    super.key,
    required this.studentId,
    required this.examDetails,
  });

  @override
  State<ExamHistoryPage> createState() => _ExamHistoryPageState();
}

class _ExamHistoryPageState extends State<ExamHistoryPage> {
  // Grouped by "Date | CourseCode"
  Map<String, List<ExamHistoryModel>> _flatGroupedExams = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _selectedExamKey; // Track selected summary key (Date | CourseCode)

  @override
  void initState() {
    super.initState();
    _loadExamHistory();
  }

  Future<void> _loadExamHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final s3Service = S3ExamHistoryService();
      final exams = await s3Service.fetchStudentExamHistory(widget.studentId);

      if (mounted) {
        _updateGrouping(exams);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading exam history: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}';
          _isLoading = false;
        });
      }
    }
  }

  void _updateGrouping(List<ExamHistoryModel> exams) {
    final Map<String, List<ExamHistoryModel>> freshGrouped = {};

    for (var exam in exams) {
      // Key format: "Date | CourseCode"
      final key = "${exam.formattedDate} | ${exam.courseCode}";

      if (!freshGrouped.containsKey(key)) {
        freshGrouped[key] = [];
      }
      freshGrouped[key]!.add(exam);
    }

    if (mounted) {
      setState(() {
        _flatGroupedExams = freshGrouped;
      });
    }
  }

  Future<void> _selectExam(String key) async {
    setState(() {
      _selectedExamKey = key;
      _isLoading = true;
    });

    try {
      final s3Service = S3ExamHistoryService();
      final detailedExams = await s3Service.fetchDetails(
        _flatGroupedExams[key]!,
      );

      if (mounted) {
        setState(() {
          _flatGroupedExams[key] = detailedExams;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(
          _selectedExamKey != null
              ? 'Exam Details'
              : 'Exam History ${_flatGroupedExams.isNotEmpty ? "(${_flatGroupedExams.length})" : ""}',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF000000),
          ),
        ),
        backgroundColor: const Color(0xFFFFFFFF),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF000000)),
          onPressed: () {
            if (_selectedExamKey != null) {
              setState(() => _selectedExamKey = null);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadExamHistory,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Color(0xFF444CE7)),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                color: Color(0xFF535862),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadExamHistory,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_flatGroupedExams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_edu, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No exam history found for ${widget.studentId}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF535862),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Uploaded answer sheets will appear here.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: Color(0xFF717680),
              ),
            ),
          ],
        ),
      );
    }

    // If an exam is selected, show its individual questions/PDFs
    if (_selectedExamKey != null) {
      return _buildQuestionsView(_selectedExamKey!);
    }

    // Otherwise, show the flat summary list
    return _buildFlatSummaryListView();
  }

  // Show the summary format: "Date | Coursecode - Count"
  Widget _buildFlatSummaryListView() {
    final keys = _flatGroupedExams.keys.toList()
      ..sort((a, b) {
        // Sort by the most recent exam date in the group
        final latestA = _flatGroupedExams[a]!
            .map((e) => e.examDate)
            .reduce((max, e) => e.isAfter(max) ? e : max);
        final latestB = _flatGroupedExams[b]!
            .map((e) => e.examDate)
            .reduce((max, e) => e.isAfter(max) ? e : max);
        return latestB.compareTo(latestA);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        final exams = _flatGroupedExams[key]!;

        // Filter out Front Page (questionNumber == 0) for the count
        final answerCount = exams.where((e) => e.questionNumber != 0).length;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            border: Border.all(color: const Color(0xFFE9EAEB), width: 1),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(10, 13, 18, 0.05),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _selectExam(key),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            key,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF181D27),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "No.of.Answer: $answerCount",
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              color: Color(0xFF717680),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFF717680)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Questions view for a specific Date | CourseCode pair
  Widget _buildQuestionsView(String key) {
    final exams = List<ExamHistoryModel>.from(_flatGroupedExams[key] ?? [])
      ..sort((a, b) => a.questionNumber.compareTo(b.questionNumber));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: exams.length,
      itemBuilder: (context, index) {
        final exam = exams[index];
        return _buildQuestionCard(exam);
      },
    );
  }

  // Question card (Answer Sheet)
  Widget _buildQuestionCard(ExamHistoryModel exam) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        border: Border.all(color: const Color(0xFFE9EAEB), width: 1),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(10, 13, 18, 0.05),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  exam.displayName,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
                if (exam.pageCount != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF444CE7).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${exam.pageCount} Pages',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF444CE7),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${exam.formattedDate} | ${exam.formattedTime}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Color(0xFF717680),
              ),
            ),
            const SizedBox(height: 4),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 244, 247, 245),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color.fromARGB(255, 203, 202, 202),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Color(0xFF087443),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        exam.status,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color.fromARGB(255, 0, 4, 2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
