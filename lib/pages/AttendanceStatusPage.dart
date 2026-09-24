import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:supervisorapp/Services/ExcelService.dart';
import 'package:supervisorapp/Services/violation/tab_switch_service.dart';
import 'package:supervisorapp/core/network/api_client.dart';

class AttendanceStatusPage extends StatefulWidget {
  final String supervisorId;
  final String centre;
  final String courseCode;
  final String session;

  const AttendanceStatusPage({
    super.key,
    required this.supervisorId,
    required this.centre,
    required this.courseCode,
    required this.session,
  });

  @override
  State<AttendanceStatusPage> createState() => _AttendanceStatusPageState();
}

class _AttendanceStatusPageState extends State<AttendanceStatusPage>
    with SingleTickerProviderStateMixin {
  int _total = 0;
  int _completed = 0;
  List<dynamic> _students = [];
  String _selectedFilter = 'All';
  final S3TimeoutService _s3Service = S3TimeoutService();
  bool _isLoading = true;
  bool _isFetching = false;

  Timer? _pollingTimer;
  late AnimationController _pulseController;

  int get _notStartedCount =>
      _students.where((s) => s['status'] == 'Not Started').length;
  int get _pendingCount => _students
      .where((s) => s['status'] == 'Pending' || s['status'] == 'In Progress')
      .length;
  int get _violationCount =>
      _students.where((s) => s['status'] == 'Violation').length;
  int get _timeoutCount =>
      _students.where((s) => s['status'] == 'Timeout').length;
  int get _completedCount =>
      _students.where((s) => s['status'] == 'Completed').length;

  List<dynamic> get _filteredStudents {
    if (_selectedFilter == 'All') return _students;
    if (_selectedFilter == 'Pending') {
      return _students
          .where(
            (s) => s['status'] == 'Pending' || s['status'] == 'In Progress',
          )
          .toList();
    }
    return _students.where((s) => s['status'] == _selectedFilter).toList();
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _fetchStatus();
    _pollingTimer = Timer.periodic(const Duration(seconds: 12), (timer) {
      _fetchStatus(isSilent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus({bool isSilent = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    if (!isSilent && mounted) setState(() => _isLoading = true);

    try {
      final result = await ExcelService.getAttendanceStatus(
        centre: widget.centre,
        courseCode: widget.courseCode,
        session: widget.session,
      );

      if (mounted && result['success'] == true) {
        if (result['debug'] != null) {
          debugPrint(' [AttendStatus Debug] ${result['debug']}');
        }

        try {
          final List<dynamic> currentStudents = result['students'] ?? [];
          if (currentStudents.isNotEmpty) {
            final centerStudentIds = currentStudents
                .map((s) => (s['studentId'] ?? '').toString())
                .where((id) => id.isNotEmpty)
                .toList();

            final currentExamList = [
              {'courseCode': widget.courseCode},
            ];

            final todayYMD = DateFormat('yyyy-MM-dd').format(DateTime.now());
            final todayDMY = DateFormat('dd-MM-yyyy').format(DateTime.now());

            // 1. Run violations, timeouts, and batch answer checks concurrently
            final parallelResults = await Future.wait([
              _s3Service.fetchTimeoutLogs(
                studentIds: centerStudentIds,
                centre: widget.centre,
                activeExams: currentExamList,
                rootPrefix: 'tabswitch_violation/',
                date: todayYMD,
                courseCode: widget.courseCode,
              ),
              _s3Service.fetchTimeoutLogs(
                studentIds: centerStudentIds,
                centre: widget.centre,
                activeExams: currentExamList,
                rootPrefix: 'Timeouts/',
                date: todayYMD,
                courseCode: widget.courseCode,
              ),
              ApiClient.sendAction(
                action: 'batchCheckCompletedAnswers',
                payload: {
                  'studentIds': centerStudentIds,
                  'courseCode': widget.courseCode,
                  'dates': [todayYMD, todayDMY],
                },
              ),
            ]);

            final violationLogs =
                parallelResults[0] as List<Map<String, String>>;
            final timeoutLogs = parallelResults[1] as List<Map<String, String>>;
            final batchAnswersResult =
                parallelResults[2] as Map<String, dynamic>;

            final violatingIds = violationLogs
                .map((log) => (log['Student ID'] ?? '').toUpperCase())
                .toSet();

            final timeoutIds = timeoutLogs
                .map((log) => (log['Student ID'] ?? '').toUpperCase())
                .toSet();

            // Seed completed answer sheets from initial attendance check + batch S3 check
            final Set<String> completedStudentIds = currentStudents
                .where((s) => (s['status'] ?? '') == 'Completed')
                .map((s) => (s['studentId'] ?? '').toString().toUpperCase())
                .toSet();

            if (batchAnswersResult['success'] == true &&
                batchAnswersResult['completedIds'] is List) {
              for (var id in batchAnswersResult['completedIds']) {
                completedStudentIds.add(id.toString().toUpperCase());
              }
            }

            // 2. Resolve student status in-memory strictly adhering to user specification:
            // Grey: Not Started (Attendance not marked yet)
            // Blue: Pending (Attendance marked, but not uploaded, not timed out, not in violation)
            // Orange: Violation (Only if student did a tab switch violation for today's active exam)
            // Red: Timeout (Only if student timed out for today's active exam)
            // Green: Completed (Answer sheet uploaded or exam marked finished)
            final List<dynamic> updatedStudents = [];
            for (var student in currentStudents) {
              final id = (student['studentId'] ?? '').toString().toUpperCase();
              final rawStatus = (student['status'] ?? '').toString();
              final bool hasAttendanceRecord =
                  rawStatus == 'In Progress' ||
                  rawStatus == 'Pending' ||
                  rawStatus == 'Completed';

              String finalStatus;
              if (completedStudentIds.contains(id) ||
                  rawStatus == 'Completed') {
                // Answer sheet uploaded or finished -> Completed (Green)
                finalStatus = 'Completed';
              } else if (violatingIds.contains(id)) {
                // Tab switch violation on today's exam -> Violation (Orange)
                finalStatus = 'Violation';
              } else if (timeoutIds.contains(id)) {
                // Timeout on today's exam -> Timeout (Red)
                finalStatus = 'Timeout';
              } else if (hasAttendanceRecord) {
                // Attendance marked in DynamoDB -> Pending (Blue)
                finalStatus = 'Pending';
              } else {
                // Attendance not marked yet -> Not Started (Grey)
                finalStatus = 'Not Started';
              }

              updatedStudents.add({...student, 'status': finalStatus});
            }

            final statusSortOrder = {
              'Completed': 0,
              'Violation': 1,
              'Timeout': 2,
              'Pending': 3,
              'Not Started': 4,
            };
            updatedStudents.sort((a, b) {
              final prioA = statusSortOrder[a['status']] ?? 99;
              final prioB = statusSortOrder[b['status']] ?? 99;
              if (prioA != prioB) return prioA.compareTo(prioB);
              return (a['studentName'] ?? '').toString().compareTo(
                (b['studentName'] ?? '').toString(),
              );
            });

            final int calculatedCompleted = updatedStudents
                .where((s) => s['status'] == 'Completed')
                .length;

            if (!mounted) return;
            setState(() {
              _total = result['total'] ?? 0;
              _completed = calculatedCompleted;
              _students = updatedStudents;
              _isLoading = false;
            });
            return;
          }
        } catch (e) {
          debugPrint(' [AttendStatus] Status resolution failed: $e');
        }

        if (!mounted) return;
        setState(() {
          _total = result['total'] ?? 0;
          _completed = result['present'] ?? 0;
          _students = (result['students'] as List<dynamic>? ?? []).map((s) {
            final raw = (s['status'] ?? '').toString();
            String st;
            if (raw == 'Completed') {
              st = 'Completed';
            } else if (raw == 'In Progress' || raw == 'Pending') {
              st = 'Pending';
            } else {
              st = 'Not Started';
            }
            return {...s, 'status': st};
          }).toList();
          _isLoading = false;
        });
      } else if (mounted && !isSilent) {
        setState(() => _isLoading = false);
      }
    } finally {
      _isFetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: Color(0xFF101828),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF444CE7)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // Clean Minimal Header
                  Text(
                    widget.courseCode,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF444CE7), // Your favorite blue
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        widget.session,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.centre,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Modern Stats Row
                  Row(
                    children: [
                      _buildMiniStat(
                        "Total",
                        "$_total",
                        Colors.grey.shade100,
                        const Color(0xFF101828),
                      ),
                      const SizedBox(width: 12),
                      _buildMiniStat(
                        "Completed",
                        "$_completed",
                        const Color(0xFF079455).withValues(alpha: 0.05),
                        const Color(0xFF079455),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Filter Chips / Status Breakdown
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildFilterChip(
                          'All',
                          _total,
                          const Color(0xFF101828),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          'Not Started',
                          _notStartedCount,
                          Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          'Pending',
                          _pendingCount,
                          const Color(0xFF444CE7),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          'Violation',
                          _violationCount,
                          Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          'Timeout',
                          _timeoutCount,
                          Colors.red.shade700,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          'Completed',
                          _completedCount,
                          const Color(0xFF079455),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // List Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedFilter == 'All'
                            ? "Student List"
                            : "$_selectedFilter Students",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF101828),
                        ),
                      ),
                      Text(
                        "${_filteredStudents.length} of $_total",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Clean Student List
                  _filteredStudents.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredStudents.length,
                          itemBuilder: (context, index) {
                            final student = _filteredStudents[index];
                            return _buildStudentTile(
                              student,
                              student['status'],
                            );
                          },
                        ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChip(String label, int count, Color color) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(
    String label,
    String value,
    Color bgColor,
    Color textColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textColor.withValues(alpha: 0.6),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentTile(dynamic student, String status) {
    Color statusColor;
    Color bgColor;
    IconData statusIcon;

    switch (status) {
      case 'Completed':
        // Green - Completed
        statusColor = const Color(0xFF079455);
        bgColor = const Color(0xFF079455).withValues(alpha: 0.1);
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'Pending':
      case 'In Progress':
        // Blue - Pending
        statusColor = const Color(0xFF444CE7);
        bgColor = const Color(0xFF444CE7).withValues(alpha: 0.1);
        statusIcon = Icons.timer_outlined;
        break;
      case 'Violation':
        // Orange - Violation (Only if student did tabswitch violation)
        statusColor = Colors.orange.shade700;
        bgColor = Colors.orange.shade50;
        statusIcon = Icons.warning_amber_rounded;
        break;
      case 'Timeout':
        // Red - Timeout (Only if student timed out)
        statusColor = Colors.red.shade700;
        bgColor = Colors.red.shade50;
        statusIcon = Icons.timer_off_outlined;
        break;
      case 'Not Started':
        // Grey - Not Started
        statusColor = Colors.grey.shade600;
        bgColor = Colors.grey.withValues(alpha: 0.08);
        statusIcon = Icons.schedule;
        break;
      case 'Absent':
        statusColor = Colors.grey.shade600;
        bgColor = Colors.grey.withValues(alpha: 0.12);
        statusIcon = Icons.person_off_outlined;
        break;
      default:
        statusColor = Colors.grey.shade600;
        bgColor = Colors.grey.withValues(alpha: 0.1);
        statusIcon = Icons.person_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: bgColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: bgColor.withValues(alpha: 0.2)),
            ),
            child: Icon(statusIcon, color: statusColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student['studentName'] ?? 'Unknown',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101828),
                    fontSize: 16,
                  ),
                ),
                Text(
                  student['studentId'] ?? '',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status == 'In Progress' ? 'Pending' : status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              _selectedFilter == 'All'
                  ? "No students registered for this session"
                  : "No students with status '$_selectedFilter'",
              style: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
