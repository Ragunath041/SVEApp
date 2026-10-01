// ignore_for_file: use_build_context_synchronously, file_names

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supervisorapp/Services/auth/supervisor_auth_service.dart';
import 'package:supervisorapp/Services/ExamDetailsService.dart';
import 'package:supervisorapp/pages/incident.dart';
import 'package:supervisorapp/pages/AttendanceReportUploadPage.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:supervisorapp/widgets/UploadAnswerSheetDialog.dart';
import 'package:supervisorapp/pages/tabswitch_page.dart';
import 'package:supervisorapp/Services/violation/tab_switch_service.dart';
import 'package:supervisorapp/widgets/QRScannerPage.dart';
import 'package:supervisorapp/Services/ExamDetailsLambdaService.dart';
import 'package:supervisorapp/Services/proctor/super_proctor_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

class ExamDashboard extends StatefulWidget {
  final String supervisorId;
  final String fullName;
  final String centre;

  const ExamDashboard({
    super.key,
    required this.supervisorId,
    required this.fullName,
    required this.centre,
  });

  @override
  State<ExamDashboard> createState() => _ExamDashboardState();
}

class _ExamDashboardState extends State<ExamDashboard> {
  late String _fullName;
  late String _centre;
  final DynamoDBService _dynamoDBService = DynamoDBService();
  String? _activeSuperProctorCode;

  bool _hasNewNotification = false;
  int _lastLogCount = 0;
  Timer? _pollingTimer;
  final S3TimeoutService _s3Service = S3TimeoutService();

  // Cache active exams for 30s to avoid hitting DynamoDB every second
  List<Map<String, dynamic>>? _cachedActiveExams;
  DateTime? _lastActiveExamFetch;
  static const _activeExamCacheDuration = Duration(seconds: 30);

  // Guard against overlapping concurrent checks
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _fullName =
        (widget.fullName.isNotEmpty &&
            widget.fullName.toLowerCase() != 'unknown' &&
            widget.fullName != 'Supervisor')
        ? widget.fullName.trim()
        : '';
    _centre =
        (widget.centre.isNotEmpty && widget.centre.toLowerCase() != 'unknown')
        ? widget.centre.trim()
        : '';
    _fetchLiveSupervisorDetails();
    _initializeNotifications();
    // _fetchActiveSuperProctorCode();
  }

  /// Fetches supervisor details directly from DynamoDB (bits-Supervisor-details)
  Future<void> _fetchLiveSupervisorDetails() async {
    try {
      final liveResult = await _dynamoDBService.getSupervisorDetails(
        widget.supervisorId,
      );
      if (liveResult['success'] == true && mounted) {
        final d = liveResult['data'] as Map<String, dynamic>;
        final liveName = (d['name'] ?? d['full_name'] ?? d['Name'])
            ?.toString()
            .trim();
        final liveCentre = (d['centre'] ?? d['Exam hall'] ?? d['center'])
            ?.toString()
            .trim();

        setState(() {
          if (liveName != null && liveName.isNotEmpty) {
            _fullName = liveName;
          }
          if (liveCentre != null && liveCentre.isNotEmpty) {
            _centre = liveCentre;
          }
        });
        // _fetchActiveSuperProctorCode();
        debugPrint(
          '[ExamDashboard] Live supervisor details fetched from DynamoDB: Name="$_fullName", Centre="$_centre"',
        );
      }
    } catch (e) {
      debugPrint('[ExamDashboard] Error fetching supervisor details: $e');
    }
  }

  Future<void> _initializeNotifications() async {
    await _loadPersistedCount();
    if (!mounted) return;

    // Initial check on load
    _checkForNotifications();

    // Poll every 1 second for near real-time accuracy
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkForNotifications();
    });
  }

  Future<void> _loadPersistedCount() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _lastLogCount =
            prefs.getInt('last_violation_count_${widget.centre}') ?? 0;
      });
    }
  }

  Future<void> _savePersistedCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_violation_count_${widget.centre}', count);
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkForNotifications() async {
    // Skip if a check is already in progress
    if (_isChecking) return;
    _isChecking = true;

    try {
      final now = DateTime.now();

      // 1. Get active exams — re-fetch from DynamoDB only every 30 seconds
      if (_cachedActiveExams == null ||
          _lastActiveExamFetch == null ||
          now.difference(_lastActiveExamFetch!) > _activeExamCacheDuration) {
        _cachedActiveExams = await ExamDetailsService.getCenterActiveExams(
          widget.centre,
        );
        _lastActiveExamFetch = now;
      }
      final activeExams = _cachedActiveExams!;

      // No active exam → clear dot, no S3 call needed
      if (activeExams.isEmpty) {
        if (mounted && _lastLogCount != 0) {
          setState(() => _lastLogCount = 0);
        }
        return;
      }

      // 2. Count violations via S3 list only (zero file downloads)
      final count = await _s3Service.countViolationsForActiveSession(
        centre: widget.centre,
        activeExams: activeExams,
      );

      debugPrint(' [Dashboard] Violation count for active session: $count');

      if (!mounted) return;

      if (count > _lastLogCount) {
        // New violation(s) arrived
        setState(() {
          _hasNewNotification = true;
          _lastLogCount = count;
        });
        _savePersistedCount(count);
      } else if (count < _lastLogCount) {
        // Session changed or logs cleared — reset baseline
        setState(() => _lastLogCount = count);
        _savePersistedCount(count);
      }
      // count == _lastLogCount → no change, dot stays as-is
    } catch (e) {
      debugPrint(' [Dashboard] Error polling notifications: $e');
    } finally {
      _isChecking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double scale = (screenWidth / 375.0).clamp(0.85, 1.15);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/images/company_logo.png',
                width: 35,
                height: 35,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 10 * scale),
            Expanded(
              child: Text(
                'Supervisor Manager',
                style: TextStyle(
                  fontSize: 17 * scale,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16.0 * scale,
            vertical: 8.0 * scale,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title Header
              Center(
                child: Text(
                  "Examination Dashboard",
                  style: TextStyle(
                    fontSize: (18 * scale).clamp(16.0, 20.0),
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              SizedBox(height: 8 * scale),

              // Supervisor & Centre Information Card
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 14 * scale,
                  vertical: 10 * scale,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                      "Supervisor Name:",
                      _fullName.isNotEmpty &&
                              _fullName.toLowerCase() != 'unknown'
                          ? _fullName
                          : (widget.fullName.trim().isNotEmpty &&
                                    widget.fullName.trim().toLowerCase() !=
                                        'unknown'
                                ? widget.fullName.trim()
                                : 'Loading...'),
                      scale,
                    ),
                    SizedBox(height: 6 * scale),
                    _buildInfoRow("Supervisor ID:", widget.supervisorId, scale),
                    SizedBox(height: 6 * scale),
                    _buildInfoRow(
                      "Center Name:",
                      _centre.isNotEmpty && _centre.toLowerCase() != 'unknown'
                          ? _centre
                          : (widget.centre.trim().isNotEmpty &&
                                    widget.centre.trim().toLowerCase() !=
                                        'unknown'
                                ? widget.centre.trim()
                                : 'Loading...'),
                      scale,
                    ),
                  ],
                ),
              ),

              SizedBox(height: 10 * scale),

              // Upload Answer Sheet Button
              _buildActionButton(
                icon: Icons.file_upload_outlined,
                label: "Upload Answer Sheet",
                backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                foregroundColor: Colors.white,
                onPressed: () {
                  _showUploadAnswerSheetWithLoading(context);
                },
                scale: scale,
              ),

              SizedBox(height: 10 * scale),

              // Upload Attendance Report Button
              _buildActionButton(
                icon: Icons.assignment_ind_outlined,
                label: "Upload Attendance Report",
                backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                foregroundColor: Colors.white,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => AttendanceReportUploadPage(
                        centre: _centre.isNotEmpty ? _centre : widget.centre,
                        supervisorId: widget.supervisorId,
                      ),
                    ),
                  );
                },
                scale: scale,
              ),

              SizedBox(height: 10 * scale),

              // Upload Incident Report Button
              _buildActionButton(
                icon: Icons.description_outlined,
                label: "Upload Incident Report",
                backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                foregroundColor: Colors.white,
                onPressed: () {
                  _showUploadIncidentReportDialog(context);
                },
                scale: scale,
              ),

              SizedBox(height: 10 * scale),

              // View Notifications Button with badge
              _buildActionButton(
                icon: Icons.notifications_outlined,
                label: "View Notifications",
                backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                foregroundColor: Colors.white,
                trailing: _hasNewNotification
                    ? Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 7 * scale,
                          vertical: 2 * scale,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.35),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: Text(
                          "NEW",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9 * scale,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      )
                    : null,
                onPressed: () {
                  setState(() {
                    _hasNewNotification = false;
                  });
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => TabSwitchPage(
                        centre: _centre.isNotEmpty ? _centre : widget.centre,
                      ),
                    ),
                  );
                },
                scale: scale,
              ),

              SizedBox(height: 8 * scale),

              // ── QR Scan Button (old-style centered design) ──
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              GestureDetector(
                onTap: () async {
                  final result = await Navigator.of(context)
                      .push<ScannedStudentData>(
                        MaterialPageRoute(
                          builder: (context) =>
                              QRScannerPage(supervisorId: widget.supervisorId),
                        ),
                      );
                  if (result != null && mounted) {
                    await _handleQRScanResult(result);
                  }
                },
                child: Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 20 * scale),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        size: 30 * scale,
                        color: const Color.fromARGB(255, 120, 130, 235),
                      ),
                      SizedBox(height: 8 * scale),
                      Text(
                        "Scan QR Code",
                        style: TextStyle(
                          color: const Color.fromARGB(255, 120, 130, 235),
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppFooter(),
    );
  }

  Future<void> _handleQRScanResult(ScannedStudentData studentData) async {
    // Show a loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              Color.fromARGB(255, 68, 76, 231),
            ),
          ),
        );
      },
    );

    try {
      // Get current local scan time and date
      final now = DateTime.now();
      final String scannedTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final String scannedDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final response = await ExamDetailsLambdaService.saveScannedStudentData(
        studentData,
        scannedTime,
        scannedDate,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Student ${studentData.name} (${studentData.bitsId}) verified successfully!',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response['error'] ?? 'Failed to save verification data.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Verification error: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Show Upload Incident Report Dialog
  void _showUploadIncidentReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Text(
                  "Upload Incident Report",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 24),

                // Supervisor Information
                _buildDialogInfoRow(
                  "Supervisor Name:",
                  _fullName.isNotEmpty && _fullName.toLowerCase() != 'unknown'
                      ? _fullName
                      : (widget.fullName.trim().isNotEmpty
                            ? widget.fullName.trim()
                            : 'Supervisor'),
                ),
                SizedBox(height: 12),
                _buildDialogInfoRow("Supervisor ID:", widget.supervisorId),
                SizedBox(height: 12),
                _buildDialogInfoRow(
                  "Center Name:",
                  _centre.isNotEmpty ? _centre : widget.centre,
                ),

                SizedBox(height: 24),

                // Proceed Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Close dialog
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => IncidentReportPage(
                            centre: _centre.isNotEmpty
                                ? _centre
                                : widget.centre,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(255, 68, 76, 231),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        "Proceed",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper method to build dialog info rows
  Widget _buildDialogInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.right,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Helper method to build info rows
  Widget _buildInfoRow(String label, String value, [double scale = 1.0]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14 * scale, color: Colors.grey.shade700),
        ),
        SizedBox(width: 8 * scale),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14 * scale,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.right,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Helper method to build action buttons
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onPressed,
    Widget? trailing,
    double scale = 1.0,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          padding: EdgeInsets.symmetric(
            vertical: 30 * scale,
            horizontal: 14 * scale,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: Row(
          children: [
            Icon(icon, size: 25 * scale, color: foregroundColor),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w600,
                  color: foregroundColor,
                ),
              ),
            ),
            if (trailing != null) ...[
              SizedBox(width: 6 * scale),
              trailing,
            ] else ...[
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13 * scale,
                color: foregroundColor.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Show Upload Answer Sheet dialog with loading
  void _showUploadAnswerSheetWithLoading(BuildContext context) async {
    final navigator = Navigator.of(
      context,
    ); // Capture navigator before async boundary

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext loadingContext) {
        return PopScope(
          canPop: false,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: Color.fromARGB(255, 68, 76, 231),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Loading student data...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Please wait',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Load student IDs from S3 (filtered by center)
    try {
      final studentIds = await ExamDetailsService.getAllStudentIds(
        centerFilter: _centre.isNotEmpty ? _centre : widget.centre,
      );

      if (mounted) {
        navigator.pop(); // Close loading dialog

        // Show main dialog with pre-loaded data
        showDialog(
          context: context,
          builder: (context) => UploadAnswerSheetDialog(
            supervisorName:
                _fullName.isNotEmpty && _fullName.toLowerCase() != 'unknown'
                ? _fullName
                : widget.fullName,
            supervisorId: widget.supervisorId,
            centre: _centre.isNotEmpty ? _centre : widget.centre,
            preloadedStudentIds: studentIds,
          ),
        );
      }
    } catch (e) {
      if (navigator.context.mounted) {
        navigator.pop(); // Close loading dialog

        // Show error
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to load student records. Please check your network.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint("Failed to load student data: $e");
    }
  }
}
