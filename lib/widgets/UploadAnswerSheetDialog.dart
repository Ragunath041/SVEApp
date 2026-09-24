import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supervisorapp/Services/ExamDetailsService.dart';
import 'package:supervisorapp/pages/uploadPage.dart';
import 'package:supervisorapp/Services/attendance/student_attendance_service.dart';
import 'package:supervisorapp/Services/exam/exam_progress_service.dart';
import 'package:geolocator/geolocator.dart';

class UploadAnswerSheetDialog extends StatefulWidget {
  final String supervisorName;
  final String supervisorId;
  final String centre;
  final String title;
  final List<String>? preloadedStudentIds;
  // Callback to build the destination page after selection
  final Widget Function(
    BuildContext context,
    String studentId,
    Map<String, String> selectedExam,
    String? attendanceId,
  )?
  destinationBuilder;

  const UploadAnswerSheetDialog({
    super.key,
    required this.supervisorName,
    required this.supervisorId,
    required this.centre,
    this.title = "Upload Answer Sheet",
    this.preloadedStudentIds,
    this.destinationBuilder,
  });

  @override
  State<UploadAnswerSheetDialog> createState() =>
      _UploadAnswerSheetDialogState();
}

class _UploadAnswerSheetDialogState extends State<UploadAnswerSheetDialog> {
  final TextEditingController _studentIdController = TextEditingController();

  bool _isLoading = false;
  bool _dataFetched = false;
  String _loadingMessage = 'Validating Student ID...';

  String? _studentName;
  String? _studentCentre;
  List<Map<String, String>>? _exams;
  String? _selectedCourseCode;
  bool get _isHistoryMode => widget.title == "Exam History";

  // Student IDs loaded from S3
  List<String> _allStudentIds = [];

  @override
  void initState() {
    super.initState();

    // Use preloaded data if available, otherwise load from S3
    if (widget.preloadedStudentIds != null &&
        widget.preloadedStudentIds!.isNotEmpty) {
      _allStudentIds = widget.preloadedStudentIds!;
      // print(' Using ${_allStudentIds.length} preloaded student IDs');
    } else {
      _loadStudentIdsFromS3(); // Fallback: Load from S3
    }
  }

  @override
  void dispose() {
    _studentIdController.dispose();

    super.dispose();
  }

  Future<void> _loadStudentIdsFromS3() async {
    setState(() {
      // _isLoadingStudentIds = true;
    });

    try {
      // print(' Loading student IDs from S3...');
      // Use ExamDetailsService to get IDs filtered by the supervisor's center
      final studentIds = await ExamDetailsService.getAllStudentIds(
        centerFilter: widget.centre,
      );

      if (studentIds.isNotEmpty) {
        setState(() {
          _allStudentIds = studentIds;
          // _isLoadingStudentIds = false;
        });

        // print(' Loaded ${studentIds.length} student IDs for center ${widget.centre}');
      } else {
        setState(() {
          // _isLoadingStudentIds = false;
        });

        // print(' No student IDs found for center ${widget.centre}');
      }
    } catch (e) {
      setState(() {
        // _isLoadingStudentIds = false;
      });

      // print(' Error loading student IDs: $e');
    }
  }

  Future<void> _fetchExamDetails() async {
    final studentId = _studentIdController.text.trim();

    if (studentId.isEmpty) {
      _showErrorDialog('Please enter a Student ID.');
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Checking cache...';
    });

    // Safety timeout - ensure we reset loading state after 9 seconds no matter what
    Future.delayed(Duration(seconds: 9), () {
      if (_isLoading && mounted) {
        // print(' Safety timeout triggered - resetting loading state');
        setState(() {
          _isLoading = false;
        });
        _showErrorDialog(
          'Request timed out. Please check your internet connection and try again.',
        );
      }
    });

    // Update message after a short delay to show we're working
    Future.delayed(Duration(milliseconds: 500), () {
      if (_isLoading && mounted) {
        setState(() {
          _loadingMessage = 'Downloading exam data...';
        });
      }
    });

    // Update message again after 2 seconds
    Future.delayed(Duration(seconds: 2), () {
      if (_isLoading && mounted) {
        setState(() {
          _loadingMessage = 'Validating Student ID...';
        });
      }
    });

    try {
      final result = await ExamDetailsService.getStudentExamDetails(studentId);

      // Only process if still loading (not timed out by safety mechanism)
      if (!_isLoading) {
        // print(' Request completed but safety timeout already triggered');
        return;
      }

      setState(() {
        _isLoading = false;
      });

      if (result['success'] == true) {
        final studentCentre = (result['centre'] ?? '').toString().trim();
        final supervisorCentre = widget.centre.trim();

        // ── Center Mismatch Check (skip in History mode) ──────────────────────
        if (!_isHistoryMode &&
            studentCentre.isNotEmpty &&
            supervisorCentre.isNotEmpty &&
            studentCentre.toLowerCase() != supervisorCentre.toLowerCase()) {
          _showCenterMismatchDialog(
            supervisorCentre: supervisorCentre,
            studentCentre: studentCentre,
          );
          return; // Block further processing
        }
        // ─────────────────────────────────────────────────────────────────────

        setState(() {
          _dataFetched = true;
          _studentName = result['studentName'];
          _studentCentre = studentCentre;
          _exams = (result['exams'] as List<dynamic>).map((e) {
            final raw = e as Map<String, dynamic>;
            return raw.map((k, v) => MapEntry(k, v?.toString() ?? ''));
          }).toList();

          // Sort exams by session priority: FN = 1, AN = 2, EN = 3
          final sessionPriority = {'FN': 1, 'AN': 2, 'EN': 3};
          _exams!.sort((a, b) {
            final pA = sessionPriority[a['session']] ?? 99;
            final pB = sessionPriority[b['session']] ?? 99;
            return pA.compareTo(pB);
          });

          // If only one exam, auto-select it
          if (_exams!.length == 1) {
            _selectedCourseCode = _exams![0]['courseCode'];
          }

          // Direct navigation for History Mode
          if (_isHistoryMode) {
            _proceedToUpload();
          }
        });
      } else {
        final errorType = result['errorType'];

        if (errorType == 'no_exam') {
          if (_isHistoryMode) {
            // In history mode, we don't care if there's no exam today.
            // Just populate student info and proceed.
            setState(() {
              _dataFetched = true;
              _studentName = result['studentName'];
              _studentCentre = result['centre'];
              _exams = [];
            });
            _proceedToUpload();
            return;
          }
          _showNoExamDialog();
        } else if (errorType == 'student_not_found') {
          if (_isHistoryMode) {
            // If student not in CSV but we are in history mode, proceed anyway.
            // They might have folders in S3 even if not in today's master sheet.
            setState(() {
              _dataFetched = true;
              _studentName = 'Unknown Student';
              _studentCentre = 'Unknown Center';
              _exams = [];
            });
            _proceedToUpload();
            return;
          }
          _showErrorDialog(
            'Student ID not found. Please verify the ID and try again.',
          );
        } else if (errorType == 'timeout') {
          _showErrorDialog(
            'Request timed out. Please check your internet connection and try again.',
          );
        } else {
          _showErrorDialog(
            result['error'] ??
                'Failed to fetch exam details. Please check your internet connection.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showErrorDialog(
          'Failed to fetch student details: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}',
        );
      }
    }
  }

  void _showCenterMismatchDialog({
    required String supervisorCentre,
    required String studentCentre,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.location_off, color: Colors.red.shade600, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Exam Centre Mismatch',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This student is allocated to a different exam centre. You can only manage students registered for your centre.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            SizedBox(height: 16),
            _buildCenterInfoRow(
              label: 'Your Center',
              value: supervisorCentre,
              icon: Icons.person_pin_circle,
              color: Colors.blue.shade700,
            ),
            SizedBox(height: 8),
            _buildCenterInfoRow(
              label: "Student's Center",
              value: studentCentre,
              icon: Icons.school,
              color: Colors.red.shade700,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color.fromARGB(255, 68, 76, 231),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text('OK, Got it'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterInfoRow({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showNoExamDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('No Exam Scheduled'),
        content: Text('No exams are scheduled for this student today.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close no exam dialog
              Navigator.pop(context); // Close main dialog
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _proceedToUpload() async {
    // If in history mode, we skip attendance and exam selection
    if (_isHistoryMode) {
      if (mounted) {
        Navigator.pop(context); // Close main dialog
        final destination = widget.destinationBuilder!(
          context,
          _studentIdController.text.trim(),
          {}, // Empty exam map
          null, // No attendance ID needed
        );
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => destination),
        );
      }
      return;
    }

    if (_selectedCourseCode == null) {
      _showErrorDialog('Please select a course to continue.');
      return;
    }

    // Find the selected exam details
    final selectedExam = _exams!.firstWhere(
      (e) => e['courseCode'] == _selectedCourseCode,
    );

    // print('Proceeding to upload with:');
    // print('Student ID: ${_studentIdController.text}');
    // print('Full Course Code: ${selectedExam['fullCourseCode']}');
    // print('Session: ${selectedExam['session']}');

    // Show loading for attendance marking
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              "Verifying Attendance...",
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );

    String? attendanceId;

    try {
      // 1. Check/Mark Attendance
      final attendanceResult = await _checkAndMarkAttendance(selectedExam);
      attendanceId = attendanceResult['attendanceId'];

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      if (attendanceResult['success'] == false) {
        // Log warning but allow proceeding?
        // print(' Attendance marking issue: ${attendanceResult['error']}');
        // Optional: Show warning dialog? For now, we proceed to upload page.
      }
    } catch (e) {
      // Close loading dialog if error
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      // print(' Error in attendance flow: $e');
      // We continue to upload page even if attendance fails,
      // but maybe we should warn the user.
      // For now, proceeding as per "soft fail" requirement.
    }

    // Get today's date formatted as dd-MM-yyyy for the S3 path
    final today = DateFormat('dd-MM-yyyy').format(DateTime.now());

    if (!mounted) return;

    // Navigate to the chosen destination or default to UploadPage
    Navigator.pop(context); // Close main dialog

    final destination = widget.destinationBuilder != null
        ? widget.destinationBuilder!(
            context,
            _studentIdController.text.trim(),
            selectedExam,
            attendanceId,
          )
        : UploadPage(
            studentId: _studentIdController.text.trim(),
            studentName: _studentName!,
            centreName: _studentCentre!,
            courseCode: selectedExam['fullCourseCode']!,
            session: selectedExam['session']!,
            examDate: today,
            attendanceId: attendanceId,
            examType: selectedExam['examType'],
          );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => destination),
    );
  }

  Future<Map<String, dynamic>> _checkAndMarkAttendance(
    Map<String, String> exam,
  ) async {
    final studentId = _studentIdController.text.trim();
    final fullCourseCode = exam['fullCourseCode']!;
    final session = exam['session']!;
    // Standardize date format for DB (yyyy-MM-dd) or match Excel?
    // The previous plan uses 'yyyy-MM-dd' for DB Date field usually.
    // However, ExamDetailsService returns date from Excel which might be '29-12-2025'.
    // Let's use standard ISO for DB if possible, or keep Excel format if that's the key.
    // DynamoDBAttendanceService expects examDate in a specific format?
    // Let's look at DynamoDBAttendanceService. The plan says date is stored.
    // Let's use the current date as the 'examDate' since we are uploading NOW.
    // Or use the date from Excel if available.
    final now = DateTime.now();
    final examDate = DateFormat(
      'dd-MM-yyyy',
    ).format(now); // Matches S3 folder structure

    try {
      // 1. Check existing attendance (exact match: student + course + date + session)
      final existingAttendanceId =
          await DynamoDBAttendanceService.getExistingAttendance(
            bitsId: studentId,
            courseCode: fullCourseCode,
            examDate: examDate,
            sessionType: session,
          );

      if (existingAttendanceId != null) {
        debugPrint(
          ' ✅ Attendance already marked for $fullCourseCode ($session) on $examDate → $existingAttendanceId',
        );
        return {'success': true, 'attendanceId': existingAttendanceId};
      }

      // print(' New attendance record needed...');

      // 2. Get GPS Location
      double lat = 0.0;
      double lng = 0.0;
      try {
        final position = await _determinePosition();
        lat = position.latitude;
        lng = position.longitude;
      } catch (locError) {
        // print(' GPS Error: $locError. Using 0.0, 0.0');
      }

      // 3. Get total questions (to set pending count)
      int totalQuestions = 0;
      try {
        // We need to fetch slots to count them
        final slots = await ExamDetailsService.getQuestionSlots(
          fullCourseCode: fullCourseCode,
          date: examDate,
        );
        totalQuestions = slots.length;
        // print(' Found $totalQuestions questions for this exam');
      } catch (e) {
        // print(' Could not count questions: $e');
        totalQuestions = 15; // Default fallback?
      }

      // 4. Get Exam Times from Lambda response (populated from DynamoDB bits-exam-center-timings)
      String startTime = exam['examStartTime'] ?? '';
      String endTime = exam['examEndTime'] ?? '';

      if (startTime.isEmpty || endTime.isEmpty) {
        // This means DynamoDB had no timings for this centre+session.
        // Log a warning — times will be empty strings in the attendance record.
        debugPrint(
          ' ⚠ Warning: No DynamoDB timings for session=${exam["session"]} '
          'centre=${_studentCentre ?? "unknown"}. '
          'Check bits-exam-center-timings table.',
        );
      } else {
        debugPrint(' ✅ Using DynamoDB timings: $startTime - $endTime');
      }

      // 5. Create Attendance Record
      final success = await DynamoDBAttendanceService.saveLoginRecord(
        bitsId: studentId,
        latitude: lat,
        longitude: lng,
        loginTime: DateTime.now(),
        noOfQuestionsPending: totalQuestions,
        courseCode: fullCourseCode,
        examDate: examDate,
        examStartTime: startTime,
        examEndTime: endTime,
        sessionType: session,
        center: widget.centre,
        uploadStartTime: DateFormat('HH:mm:ss').format(DateTime.now()),
      );

      if (!success) {
        return {'success': false, 'error': 'Failed to save attendance record.'};
      }

      // Re-fetch attendance ID after save
      await Future.delayed(Duration(milliseconds: 500));

      final newAttendanceId =
          await DynamoDBAttendanceService.getExistingAttendance(
            bitsId: studentId,
            courseCode: fullCourseCode,
            examDate: examDate,
            sessionType: session,
          );

      if (newAttendanceId == null) {
        // Fallback if read-after-write consistency delay is issue
        // We can construct it manually if we knew the timestamp, but we don't.
        return {'success': true, 'attendanceId': null};
      }

      // Create initial finishedTable record
      try {
        await DynamoDBFinishedService.createInitialRecord(
          bitsId: studentId,
          attendanceId: newAttendanceId,
          courseCode: fullCourseCode.toUpperCase().replaceAll(' ', ''),
          examDate: examDate,
          sessionType: session,
        );
      } catch (dbFinishedErr) {
        debugPrint(' Failed to create finished record: $dbFinishedErr');
      }

      return {'success': true, 'attendanceId': newAttendanceId};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied.');
    }

    return await Geolocator.getCurrentPosition();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                widget.title,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 24),

              // // Supervisor Information
              // _buildInfoRow("Supervisor Name:", widget.supervisorName),
              // SizedBox(height: 12),
              // _buildInfoRow("Supervisor ID:", widget.supervisorId),
              // SizedBox(height: 12),
              // _buildInfoRow("Centre Name:", widget.centre),

              // Student ID Input
              Text(
                "Student ID",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),

              // SizedBox(height: 8),
              // Student ID Dropdown with Clear Button
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value:
                          _allStudentIds.contains(_studentIdController.text) &&
                              _studentIdController.text.isNotEmpty
                          ? _studentIdController.text
                          : null,
                      isExpanded: true,
                      disabledHint: Text(
                        _dataFetched
                            ? _studentIdController.text
                            : "No Data found",
                      ),
                      hint: Text(
                        _allStudentIds.isEmpty
                            ? "No Data found"
                            : "Select Student ID",
                      ),
                      decoration: InputDecoration(
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.blue.shade300),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        fillColor: _dataFetched
                            ? Colors.grey.shade50
                            : Colors.white,
                        filled: true,
                      ),
                      items: _allStudentIds.isEmpty
                          ? null
                          : _allStudentIds.map((id) {
                              return DropdownMenuItem<String>(
                                value: id,
                                child: Text(
                                  id,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                ),
                              );
                            }).toList(),
                      onChanged: _dataFetched
                          ? null
                          : (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _studentIdController.text = newValue;
                                });

                                // Auto-fetch in history mode
                                if (_isHistoryMode) {
                                  _fetchExamDetails();
                                }
                              }
                            },
                    ),
                  ),
                  if (_studentIdController.text.isNotEmpty &&
                      !_dataFetched) ...[
                    SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.clear, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _studentIdController.clear();
                          _dataFetched = false;
                          _studentName = null;
                          _studentCentre = null;
                          _exams = null;
                          _selectedCourseCode = null;
                        });
                      },
                      tooltip: "Clear Selection",
                    ),
                  ],
                ],
              ),

              // Action Buttons for Student Selection
              SizedBox(height: 16),
              if (!_dataFetched) ...[
                if (_studentIdController.text.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _fetchExamDetails,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color.fromARGB(255, 68, 76, 231),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _loadingMessage,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              "Proceed",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
              ] else ...[
                // Clear/Reset selection button when data is already fetched
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _studentIdController.clear();
                        _dataFetched = false;
                        _studentName = null;
                        _studentCentre = null;
                        _exams = null;
                        _selectedCourseCode = null;
                      });
                    },
                    icon: Icon(Icons.refresh, size: 18),
                    label: Text("Change Student ID"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.shade200),
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],

              // Student Details (show after fetch)
              if (_dataFetched && !_isHistoryMode) ...[
                Divider(),
                _buildInfoRow("Student Name:", _studentName ?? ''),
                SizedBox(height: 12),
                _buildInfoRow("Student Centre:", _studentCentre ?? ''),

                SizedBox(height: 12),

                // Course Selection
                Text(
                  "Course Code",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 12),

                // If single exam, show as text field
                if (_exams!.length == 1) ...[
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          () {
                            final code = _exams![0]['courseCode']!;
                            final zIndex = code.indexOf(RegExp(r'[Zz]'));
                            final formatted =
                                (zIndex > 0 &&
                                    zIndex < code.length &&
                                    code[zIndex - 1] != ' ')
                                ? '${code.substring(0, zIndex)} ${code.substring(zIndex)}'
                                : code;
                            return '${_exams![0]['examNumber']} (${_exams![0]['session']}): $formatted';
                          }(),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_exams![0]['courseName']?.isNotEmpty ?? false) ...[
                          SizedBox(height: 4),
                          Text(
                            _exams![0]['courseName']!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // If multiple exams, show radio buttons
                if (_exams!.length > 1) ...[
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: _exams!.map((exam) {
                        final courseCode = exam['courseCode']!;
                        final examNumber = exam['examNumber']!;
                        final session = exam['session']!;

                        final zIndex = courseCode.indexOf(RegExp(r'[Zz]'));
                        final formattedCode =
                            (zIndex > 0 &&
                                zIndex < courseCode.length &&
                                courseCode[zIndex - 1] != ' ')
                            ? '${courseCode.substring(0, zIndex)} ${courseCode.substring(zIndex)}'
                            : courseCode;

                        final courseName = exam['courseName'] ?? '';

                        return ListTile(
                          title: Text('$examNumber ($session): $formattedCode'),
                          subtitle: courseName.isNotEmpty
                              ? Text(
                                  courseName,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                )
                              : null,
                          leading: Radio<String>(
                            value: courseCode,
                            // ignore: deprecated_member_use
                            groupValue: _selectedCourseCode,
                            // ignore: deprecated_member_use
                            onChanged: (value) {
                              setState(() {
                                _selectedCourseCode = value;
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],

                SizedBox(height: 24),

                // Proceed Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _proceedToUpload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(255, 68, 76, 231),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      "Proceed",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
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
}
