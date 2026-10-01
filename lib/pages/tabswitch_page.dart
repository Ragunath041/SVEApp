import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supervisorapp/Services/violation/tab_switch_service.dart';
import '../Services/ExamDetailsService.dart';

class TabSwitchPage extends StatefulWidget {
  final String centre;

  const TabSwitchPage({super.key, required this.centre});

  @override
  State<TabSwitchPage> createState() => _TabSwitchPageState();
}

class _TabSwitchPageState extends State<TabSwitchPage> {
  bool _isLoading = true;
  List<Map<String, String>> _logs = [];
  List<Map<String, String>> _filteredLogs = [];

  final TabSwitchService _s3Service = TabSwitchService();

  Timer? _pollingTimer;
  bool _isChecking = false;
  List<Map<String, dynamic>>? _cachedActiveExams;
  DateTime? _lastActiveExamFetch;
  static const _activeExamCacheDuration = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _loadData(showLoading: true);
    // Poll every 1 second to get updates in real-time
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _loadData(showLoading: false);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = false}) async {
    if (_isChecking) return;
    _isChecking = true;

    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final now = DateTime.now();

      // 1. Check for active exams in this center - use 30s cache to avoid spamming DynamoDB
      if (_cachedActiveExams == null ||
          _lastActiveExamFetch == null ||
          now.difference(_lastActiveExamFetch!) > _activeExamCacheDuration) {
        _cachedActiveExams = await ExamDetailsService.getCenterActiveExams(
          widget.centre,
        );
        _lastActiveExamFetch = now;
      }
      final activeExams = _cachedActiveExams!;

      // 2. Fetch all logs from S3 for today/center
      final allLogs = await _s3Service.fetchTimeoutLogs(
        centre: widget.centre,
        activeExams: activeExams,
      );
      debugPrint(
        ' [TabSwitchPage] Total logs received from service: ${allLogs.length}',
      );

      // 3. Filter logs to only show CURRENT active session violations
      List<Map<String, String>> sessionLogs = [];

      if (activeExams.isNotEmpty) {
        for (var log in allLogs) {
          final logCourse = (log['Course'] ?? '').toUpperCase().replaceAll(
            ' ',
            '',
          );
          final logTimeRaw = log['Timeout Time'] ?? '';
          final logTimeStr = _normalizeTo24Hour(logTimeRaw);

          debugPrint(
            ' [TabSwitchPage] Checking log: Course=$logCourse, Time=$logTimeStr',
          );

          for (var active in activeExams) {
            final activeCourse = (active['courseCode'] ?? '')
                .toUpperCase()
                .replaceAll(' ', '');
            final start = _normalizeTo24Hour(active['examStartTime'] ?? '');
            final end = _normalizeTo24Hour(active['examEndTime'] ?? '');

            // Course match: Check if log course contains active course (or vice versa)
            // or if we've injected the course from the folder structure.
            bool courseMatches = false;
            if (logCourse.isNotEmpty) {
              courseMatches =
                  logCourse.contains(activeCourse) ||
                  activeCourse.contains(logCourse);
            } else {
              // If logCourse is empty, it means parsing failed or it's missing in file
              // but since allLogs was fetched using activeExams, we trust the folder.
              courseMatches = true;
            }

            if (courseMatches) {
              // Check if time is within session window
              if (logTimeStr.isNotEmpty && start.isNotEmpty && end.isNotEmpty) {
                bool isWithin =
                    logTimeStr.compareTo(start) >= 0 &&
                    logTimeStr.compareTo(end) <= 0;
                debugPrint(
                  ' [TabSwitchPage] Match found? $isWithin (Time: $logTimeStr vs [$start, $end])',
                );
                if (isWithin) {
                  sessionLogs.add(log);
                  break;
                }
              } else {
                debugPrint(
                  ' [TabSwitchPage] Missing time data: logTime=$logTimeStr, start=$start, end=$end',
                );
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _logs = sessionLogs;
          _filteredLogs = sessionLogs;
          _isLoading = false;
        });

        // 4. Update persisted baseline count so dashboard red dot resets/doesn't show duplicates
        try {
          final count = await _s3Service.countViolationsForActiveSession(
            centre: widget.centre,
            activeExams: activeExams,
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('last_violation_count_${widget.centre}', count);
          debugPrint(' [TabSwitchPage] Updated read count baseline to: $count');
        } catch (e) {
          debugPrint(' [TabSwitchPage] Error persisting violation count: $e');
        }
      }
    } catch (e) {
      debugPrint("Error loading notification data: $e");
      if (mounted && showLoading) setState(() => _isLoading = false);
    } finally {
      _isChecking = false;
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF444CE7)),
                  )
                : _filteredLogs.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredLogs.length,
                    itemBuilder: (context, index) {
                      return _buildTimeoutCard(_filteredLogs[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'No Violations Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeoutCard(Map<String, String> log) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red.shade700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log['Student ID'] ?? 'Unknown Student',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Course: ${log['Course'] ?? 'N/A'}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Violation',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _buildDetailRow('Exam Date', log['Exam Date'] ?? 'N/A'),
          _buildDetailRow('Time', log['Timeout Time'] ?? 'N/A'),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _normalizeTo24Hour(String timeStr) {
    if (timeStr.isEmpty) return '';
    try {
      timeStr = timeStr.trim().toUpperCase();

      // Handle "YYYY-MM-DD HH:mm:ss" - extract only the time part
      if (timeStr.contains(' ') &&
          (timeStr.contains('-') || timeStr.contains('/'))) {
        final parts = timeStr.split(' ');
        for (var part in parts) {
          if (part.contains(':')) {
            timeStr = part;
            break;
          }
        }
      }
      // If it already looks like 24h (HH:mm:ss) and doesn't have AM/PM
      if (!timeStr.contains('AM') && !timeStr.contains('PM')) {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          final h = parts[0].padLeft(2, '0');
          final m = parts[1].padLeft(2, '0');
          final s = parts.length > 2 ? parts[2].padLeft(2, '0') : '00';
          return '$h:$m:$s';
        }
        return timeStr;
      }

      // Handle AM/PM format
      DateFormat inputFormat;
      if (timeStr.contains(':')) {
        inputFormat = DateFormat('hh:mm:ss a');
      } else {
        inputFormat = DateFormat('hh:mm a');
      }

      final DateTime dt = inputFormat.parse(timeStr);
      return DateFormat('HH:mm:ss').format(dt);
    } catch (e) {
      return timeStr;
    }
  }
}
