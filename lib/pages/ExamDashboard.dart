import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supervisorapp/Services/auth/supervisor_auth_service.dart';
import 'package:supervisorapp/Services/ExamDetailsService.dart';
import 'package:supervisorapp/pages/uploadPage.dart';
import 'package:supervisorapp/pages/incident.dart';
import 'package:supervisorapp/pages/answer_sheet_capture.dart';
import 'package:supervisorapp/pages/AttendanceReportUploadPage.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:supervisorapp/widgets/UploadAnswerSheetDialog.dart';
import 'package:supervisorapp/Services/StorageService.dart';
import 'package:supervisorapp/pages/tabswitch_page.dart';
import 'package:supervisorapp/Services/violation/tab_switch_service.dart';
import 'package:supervisorapp/widgets/QRScannerPage.dart';
import 'package:supervisorapp/Services/ExamDetailsLambdaService.dart';

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
    _fullName = (widget.fullName.isNotEmpty &&
            widget.fullName.toLowerCase() != 'unknown' &&
            widget.fullName != 'Supervisor')
        ? widget.fullName.trim()
        : '';
    _centre = (widget.centre.isNotEmpty &&
            widget.centre.toLowerCase() != 'unknown')
        ? widget.centre.trim()
        : '';
    _fetchLiveSupervisorDetails();
    _initializeNotifications();
  }

  /// Fetches supervisor details directly from DynamoDB (bits-Supervisor-details)
  Future<void> _fetchLiveSupervisorDetails() async {
    try {
      final liveResult = await _dynamoDBService.getSupervisorDetails(
        widget.supervisorId,
      );
      if (liveResult['success'] == true && mounted) {
        final d = liveResult['data'] as Map<String, dynamic>;
        final liveName =
            (d['name'] ?? d['full_name'] ?? d['Name'])?.toString().trim();
        final liveCentre =
            (d['centre'] ?? d['Exam hall'] ?? d['center'])?.toString().trim();

        setState(() {
          if (liveName != null && liveName.isNotEmpty) {
            _fullName = liveName;
          }
          if (liveCentre != null && liveCentre.isNotEmpty) {
            _centre = liveCentre;
          }
        });
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
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
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Supervisor Manager',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            tooltip: 'Logout',
            onPressed: () {
              _showLogoutDialog(context);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // const SizedBox(height: 10),
              // Title
              const Text(
                "Examination Dashboard",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              // const SizedBox(height: 30),

              // Information Table
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
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
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow("Supervisor ID:", widget.supervisorId),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      "Center Name:",
                      _centre.isNotEmpty && _centre.toLowerCase() != 'unknown'
                          ? _centre
                          : (widget.centre.trim().isNotEmpty &&
                                  widget.centre.trim().toLowerCase() !=
                                      'unknown'
                              ? widget.centre.trim()
                              : 'Loading...'),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // const SizedBox(height: 30),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildActionButton(
                    icon: Icons.notifications,
                    label: "View Notifications",
                    backgroundColor: const Color.fromARGB(255, 120, 130, 235),
                    foregroundColor: Colors.white,
                    onPressed: () {
                      setState(() {
                        _hasNewNotification = false;
                      });
                      // Navigate to the Notification Page (TabSwitchPage)
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => TabSwitchPage(
                            centre: _centre.isNotEmpty
                                ? _centre
                                : widget.centre,
                          ),
                        ),
                      );
                    },
                  ),
                  if (_hasNewNotification)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),

              // Upload Incident Report Button
              _buildActionButton(
                icon: Icons.description,
                label: "Upload Incident Report",
                backgroundColor: const Color.fromARGB(255, 120, 130, 235),
                foregroundColor: Colors.white,
                onPressed: () {
                  _showUploadIncidentReportDialog(context);
                },
              ),

              const SizedBox(height: 5),

              // Upload Answer Sheet Button
              _buildActionButton(
                icon: Icons.file_upload_outlined,
                label: "Upload Answer Sheet",
                backgroundColor: const Color.fromARGB(255, 120, 130, 235),
                foregroundColor: Colors.white,
                onPressed: () {
                  _showUploadAnswerSheetWithLoading(context);
                },
              ),

              const SizedBox(height: 5),

              // Upload Attendance Report Button
              _buildActionButton(
                icon: Icons.assignment_ind,
                label: "Upload Attendance Report",
                backgroundColor: const Color.fromARGB(255, 120, 130, 235),
                foregroundColor: Colors.white,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => AttendanceReportUploadPage(
                        centre: _centre.isNotEmpty
                            ? _centre
                            : widget.centre,
                        supervisorId: widget.supervisorId,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 5),

              // Scan QR Code Button
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
                  padding: const EdgeInsets.symmetric(vertical: 22),

                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        size: 30,
                        color: Color.fromARGB(255, 120, 130, 235),
                      ),
                      SizedBox(height: 10),
                      Text(
                        "Scan QR Code",
                        style: TextStyle(
                          color: Color.fromARGB(255, 120, 130, 235),
                          fontSize: 15,
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

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/', (Route<dynamic> route) => false);
              },
              child: const Text('Logout', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
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
                  _fullName.isNotEmpty &&
                          _fullName.toLowerCase() != 'unknown'
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(255, 68, 76, 231),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
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

  // Show Upload Answer Sheet Dialog
  void _showUploadAnswerSheetDialog(BuildContext context) {
    final TextEditingController studentIdController = TextEditingController();
    final BuildContext outerContext = context; // Capture the outer context

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
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
                  "Upload Answer Sheet",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 24),

                // Supervisor Information
                _buildDialogInfoRow(
                  "Supervisor Name:",
                  _fullName.isNotEmpty &&
                          _fullName.toLowerCase() != 'unknown'
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
                // Student ID Input
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Student ID",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: studentIdController,
                  decoration: InputDecoration(
                    hintText: "Enter Student ID",
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.blue.shade300),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                // Proceed Button
                SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final studentId = studentIdController.text.trim();

                      // Validate student ID
                      if (studentId.isEmpty) {
                        ScaffoldMessenger.of(outerContext).showSnackBar(
                          SnackBar(
                            content: Text('Please enter a Student ID'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // Close dialog
                      Navigator.of(dialogContext).pop();

                      // Navigate to UploadPage with required parameters
                      Navigator.of(outerContext).push(
                        MaterialPageRoute(
                          builder: (context) => UploadPage(
                            studentId: studentId,
                            studentName: '',
                            centreName: _centre.isNotEmpty
                                ? _centre
                                : widget.centre,
                            courseCode: '',
                            session: '',
                            examDate: '',
                            examType:
                                null, // No exam type in this deprecated flow
                          ),
                        ),
                      );
                    },
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(255, 68, 76, 231),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
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
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 15,
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
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: foregroundColor),
              SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
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
        return WillPopScope(
          onWillPop: () async => false,
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

      if (navigator.context.mounted) {
        navigator.pop(); // Close loading dialog

        // Show main dialog with pre-loaded data
        showDialog(
          context: navigator.context,
          builder: (context) => UploadAnswerSheetDialog(
            supervisorName: _fullName.isNotEmpty &&
                    _fullName.toLowerCase() != 'unknown'
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

  // Handle Attendance Sheet Upload
  void _handleUploadAttendanceSheet(BuildContext context) async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No camera available on this device."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      List<String> capturedImages = [];
      bool addingImages = true;

      while (addingImages) {
        // Navigate to a dedicated capture screen
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                AnswerSheetCameraScreen(camera: cameras.first),
          ),
        );

        // If user backs out of camera without capturing
        if (result == null) {
          if (capturedImages.isEmpty) {
            return; // Cancelled completely
          }
          // If they have images, ask if they want to stop or continue?
          // For now, let's assume backing out means they are done capturing if they have images.
          bool? confirmStop = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text("Stop Capturing?"),
              content: Text(
                "Do you want to submit the ${capturedImages.length} captured page(s) or cancel?",
              ),
              actions: [
                TextButton(
                  child: Text("Cancel All"),
                  onPressed: () => Navigator.pop(ctx, false),
                ),
                TextButton(
                  child: Text("Submit Captured"),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          );

          if (confirmStop == true) {
            addingImages = false;
            break;
          } else if (confirmStop == false) {
            return; // Cancel everything
          } else {
            continue; // Dismissed dialog, maybe go back to camera? Or just stop.
          }
        }

        if (result is String) {
          if (!context.mounted) return;

          // Show confirmation/accept-reject dialog for THIS IMAGE
          final accepted = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: Image.file(
                        File(result),
                        height: 300,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              icon: Icon(Icons.close, color: Colors.red),
                              label: Text(
                                "Retake",
                                style: TextStyle(color: Colors.red),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade50,
                                elevation: 0,
                                padding: EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: Colors.red.shade200),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              icon: Icon(Icons.check, color: Colors.white),
                              label: Text(
                                "Keep",
                                style: TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                elevation: 0,
                                padding: EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );

          if (accepted == true) {
            capturedImages.add(result);

            // Ask to add more
            if (!context.mounted) return;
            final wantMore = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: Text("Page Added"),
                content: Text(
                  "You have captured ${capturedImages.length} page. Do you want to add another page ?",
                ),
                actions: [
                  TextButton(
                    child: Text("No"),
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                  TextButton(
                    child: Text("Yes"),
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ],
              ),
            );

            if (wantMore != true) {
              addingImages = false;
            }
          } else {
            // Retake - just loop again
            continue;
          }
        }
      } // end while

      if (capturedImages.isEmpty) return;

      if (!context.mounted) return;

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => Center(child: CircularProgressIndicator()),
      );

      try {
        // Determine session
        final now = DateTime.now();
        String session = "FN";
        final hour = now.hour;
        if (hour >= 13 && hour < 18) {
          session = "AN";
        } else if (hour >= 18) {
          session = "EN"; // Just in case
        }

        final dateStr = DateFormat('yyyy-MM-dd').format(now);

        final storageService = StorageService();
        final uploadResult = await storageService.uploadAttendanceSheetImages(
          // Use new multi-image method
          imagePaths: capturedImages,
          date: dateStr,
          session: session,
          centre: _centre.isNotEmpty ? _centre : widget.centre,
        );
        storageService.dispose();

        if (context.mounted) Navigator.pop(context); // Close loading

        if (uploadResult['success'] == true) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  uploadResult['message'] ??
                      "Attendance sheets uploaded successfully!",
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Upload failed: ${uploadResult['error'] ?? 'Please try again.'}",
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint("Attendance upload system error: $e");
        if (context.mounted) Navigator.pop(context); // Close loading
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Failed to upload attendance sheets. Please check your connection and try again.",
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not access camera. Please check permissions."),
            backgroundColor: Colors.red,
          ),
        );
        debugPrint("Camera access error: $e");
      }
    }
  }
}
