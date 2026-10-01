// ignore_for_file: empty_catches, use_build_context_synchronously

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supervisorapp/Services/ExcelService.dart';
import 'package:supervisorapp/pages/ExamDashboard.dart';
import 'package:supervisorapp/pages/modifyRegister.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:supervisorapp/pages/login.dart';
import 'package:supervisorapp/pages/incident_logs_page.dart';
import 'package:supervisorapp/Services/StorageService.dart';
import 'package:supervisorapp/pages/AttendanceStatusPage.dart';
import 'package:supervisorapp/pages/SessionHistoryPage.dart';
import 'package:supervisorapp/Services/auth/supervisor_auth_service.dart';
import 'package:flutter/services.dart';
import 'package:supervisorapp/Services/proctor/super_proctor_service.dart';

class HomePage extends StatefulWidget {
  final String supervisorId;
  final String fullName;
  final String centre;
  final String invigilatorType;

  const HomePage({
    super.key,
    required this.supervisorId,
    required this.fullName,
    required this.centre,
    required this.invigilatorType,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Live profile data fetched directly from DynamoDB backend
  late String _fullName;
  late String _centre;
  late String _invigilatorType;
  String? _superProctorCode;
  bool _isLoadingSuperProctorCode = false;

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
    _invigilatorType =
        (widget.invigilatorType.isNotEmpty &&
            widget.invigilatorType.toLowerCase() != 'unknown')
        ? widget.invigilatorType.trim()
        : '';

    // Fetch directly from DynamoDB backend (do NOT fetch from local storage)
    _fetchLiveSupervisorDetails();
    _fetchActiveSuperProctorCode();
  }

  /// Fetches supervisor details directly from DynamoDB (bits-Supervisor-details)
  Future<void> _fetchLiveSupervisorDetails() async {
    try {
      final liveResult = await DynamoDBService().getSupervisorDetails(
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
        final liveType = (d['type'] ?? d['invigilator_type'] ?? d['Type'])
            ?.toString()
            .trim();

        setState(() {
          if (liveName != null && liveName.isNotEmpty) {
            _fullName = liveName;
          }
          if (liveCentre != null && liveCentre.isNotEmpty) {
            _centre = liveCentre;
          }
          if (liveType != null && liveType.isNotEmpty) {
            _invigilatorType = liveType;
          }
        });
        _fetchActiveSuperProctorCode();
      } else {
        debugPrint('[HomePage] Failed to fetch live supervisor details: ${liveResult['error']}');
      }
    } catch (e) {
      debugPrint('[HomePage] Error fetching live supervisor details: $e');
    }
  }

  void _showAttendStatusSelection() async {
    final navigator = Navigator.of(context);

    if (_centre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Centre details are loading, please try again in a moment.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 1. Show Loading Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext loadingContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: Color.fromARGB(255, 68, 76, 231),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Fetching available exams...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Center: $_centre',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      // 2. Fetch Exams for today from Lambda
      final exams = await ExcelService.fetchCenterExams(centre: _centre);

      // Sort exams by session priority: FN = 1, AN = 2, EN = 3, then by courseCode
      final sessionPriority = {'FN': 1, 'AN': 2, 'EN': 3};
      exams.sort((a, b) {
        final pA = sessionPriority[a['session']] ?? 99;
        final pB = sessionPriority[b['session']] ?? 99;
        if (pA != pB) return pA.compareTo(pB);
        return (a['courseCode'] ?? '').compareTo(b['courseCode'] ?? '');
      });

      if (!mounted) return;
      navigator.pop(); // Close loading dialog

      if (exams.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No scheduled exams found for this centre today."),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // 3. Show Selection Popup with today's exams (FN, AN, EN)
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text("Select Today's Exam"),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: exams.length,
                itemBuilder: (context, index) {
                  final exam = exams[index];
                  return ListTile(
                    leading: const Icon(
                      Icons.description_outlined,
                      color: Color.fromARGB(255, 68, 76, 231),
                    ),
                    title: Text(
                      exam['courseCode'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text("Session: ${exam['session']}"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(context); // Close selection dialog
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AttendanceStatusPage(
                            supervisorId: widget.supervisorId,
                            centre: _centre,
                            courseCode: exam['courseCode']!,
                            session: exam['session']!,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        navigator.pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Failed to load exams: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    // Calculate a scale factor based on screen width relative to a standard 375px width (iPhone 11/X size)
    // Clamped between 0.85 and 1.15 to ensure layout stays consistent on extremely small or large devices.
    final double scale = (screenWidth / 375.0).clamp(0.85, 1.15);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/images/company_logo.webp',
                width: 32 * scale,
                height: 32 * scale,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 8 * scale),
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
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Colors.red, size: 22 * scale),
            tooltip: 'Logout',
            onPressed: () {
              // Show confirmation dialog
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text('Logout'),
                    content: Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // Close dialog
                        },
                        child: Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final navigator = Navigator.of(
                            context,
                          ); // Capture navigator before popping dialog
                          navigator.pop(); // Close dialog

                          // Clear session-related data as requested
                          try {
                            final prefs = SharedPreferencesAsync();

                            // 1. Clear session markers
                            final localSessionJson = await prefs.getString(
                              'active_session_info',
                            );
                            if (localSessionJson != null) {
                              final session = jsonDecode(localSessionJson);
                              final date = session['date'];
                              final sessionName = session['session'];
                              final markKey =
                                  'attendance_${widget.supervisorId.trim()}_${date.trim()}_${sessionName.trim()}';
                              await prefs.remove(markKey);
                            }

                            // Clear today's session markers for all sessions
                            final todayStr =
                                "${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}";
                            for (var s in ['FN', 'AN', 'EN', 'Manual']) {
                              await prefs.remove(
                                'attendance_${widget.supervisorId.trim()}_${todayStr}_$s',
                              );
                            }

                            // 2. Clear all duration and timing caches
                            final storageService = StorageService();
                            await storageService.clearCurrentSessionWindow();

                            await prefs.remove('active_session_info');
                            await prefs.remove('cached_center_timings');
                            await prefs.remove('cached_supervisor_details');
                          } catch (e) {
                            debugPrint('[HomePage] Error clearing session cache on logout: $e');
                          }

                          // Navigate to Login Page
                          navigator.pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => const Login(),
                            ),
                            (Route<dynamic> route) => false,
                          );
                        },
                        child: Text(
                          'Logout',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Container(
          color: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: 20.0 * scale,
            vertical: 16.0 * scale,
          ),
          child: Column(
            children: [
              // Welcome Message
              Center(
                child: Text(
                  _fullName.isNotEmpty
                      ? "Welcome, $_fullName!"
                      : "Welcome, Supervisor!",
                  style: TextStyle(
                    fontSize: (24 * scale).clamp(18.0, 26.0),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // Information Container
              Container(
                padding: EdgeInsets.all(16 * scale),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildInfoRow("Supervisor ID:", widget.supervisorId, scale),
                    SizedBox(height: 12 * scale),
                    _buildInfoRow(
                      "Center:",
                      _centre.isNotEmpty ? _centre : "Loading...",
                      scale,
                    ),
                    SizedBox(height: 12 * scale),
                    _buildInfoRow(
                      "Invigilator Type:",
                      _invigilatorType.isNotEmpty
                          ? _invigilatorType
                          : "Loading...",
                      scale,
                    ),
                    if (SuperProctorService.isSuperProctor(
                      _invigilatorType.isNotEmpty
                          ? _invigilatorType
                          : widget.invigilatorType,
                    )) ...[
                      if (_isLoadingSuperProctorCode) ...[
                        SizedBox(height: 12 * scale),
                        const Divider(height: 1),
                        SizedBox(height: 12 * scale),
                        _buildSuperProctorLoading(context, scale),
                      ] else if (_superProctorCode != null &&
                          _superProctorCode!.isNotEmpty) ...[
                        SizedBox(height: 12 * scale),
                        const Divider(height: 1),
                        SizedBox(height: 12 * scale),
                        _buildSuperProctorDisplay(context, scale),
                      ],
                    ],
                  ],
                ),
              ),

              SizedBox(height: 12 * scale),

              // Modify Registration Details Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ModifyRegister(
                          supervisorId: widget.supervisorId,
                          fullName: _fullName,
                          currentCentre: _centre,
                          currentInvigilatorType: _invigilatorType,
                        ),
                      ),
                    );

                    // If update was successful, perform auto-logout and redirect to login
                    if (result == true && mounted) {
                      final navigator = Navigator.of(context);
                      try {
                        final prefs = SharedPreferencesAsync();

                        // 1. Clear session markers
                        final localSessionJson = await prefs.getString(
                          'active_session_info',
                        );
                        if (localSessionJson != null) {
                          final session = jsonDecode(localSessionJson);
                          final date = session['date'];
                          final sessionName = session['session'];
                          final markKey =
                              'attendance_${widget.supervisorId.trim()}_${date.trim()}_${sessionName.trim()}';
                          await prefs.remove(markKey);
                        }

                        // 2. Clear all duration and timing caches
                        final storageService = StorageService();
                        await storageService.clearCurrentSessionWindow();

                        await prefs.remove('active_session_info');
                        await prefs.remove('cached_center_timings');
                        await prefs.remove('cached_supervisor_details');
                      } catch (e) {
                        debugPrint('[HomePage] Error clearing session cache after modify: $e');
                      }

                      // Navigate to Login Page
                      if (!mounted) return;
                      navigator.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const Login()),
                        (Route<dynamic> route) => false,
                      );
                    }
                  },
                  icon: Icon(Icons.manage_accounts_outlined, size: 22 * scale),
                  label: Text(
                    "Modify Registration Details",
                    style: TextStyle(
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: 14 * scale,
                      horizontal: 16 * scale,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),

              SizedBox(height: 12 * scale),

              // Exam Dashboard Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ExamDashboard(
                          supervisorId: widget.supervisorId,
                          fullName: _fullName,
                          centre: _centre,
                        ),
                      ),
                    ).then((_) => _fetchActiveSuperProctorCode());
                  },
                  icon: Icon(Icons.dashboard_outlined, size: 22 * scale),
                  label: Text(
                    "Exam Dashboard",
                    style: TextStyle(
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: 14 * scale,
                      horizontal: 16 * scale,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              SizedBox(height: 12 * scale),

              // Attendance Status Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showAttendStatusSelection(),
                  icon: Icon(Icons.how_to_reg_outlined, size: 22 * scale),
                  label: Text(
                    "Attend Status",
                    style: TextStyle(
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: 14 * scale,
                      horizontal: 16 * scale,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),

              SizedBox(height: 12 * scale),

              // Incident History Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            IncidentLogsPage(supervisorId: widget.supervisorId),
                      ),
                    );
                  },
                  icon: Icon(Icons.assessment_outlined, size: 22 * scale),
                  label: Text(
                    "Incident History",
                    style: TextStyle(
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: 14 * scale,
                      horizontal: 16 * scale,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),

              SizedBox(height: 12 * scale),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (dialogCtx) =>
                          const Center(child: CircularProgressIndicator()),
                    );

                    try {
                      final result =
                          await ExcelService.fetchCurrentSessionHistory(
                            _centre,
                          );

                      if (!mounted) return;
                      navigator.pop();

                      if (result['success'] == true) {
                        navigator.push(
                          MaterialPageRoute(
                            builder: (navContext) => SessionHistoryPage(
                              initialSessionName:
                                  result['session'] ?? 'Current',
                              initialHistoryData:
                                  List<Map<String, dynamic>>.from(
                                    result['data'],
                                  ),
                              centre: _centre,
                            ),
                          ),
                        );
                      } else {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              result['error'] ??
                                  'No session history found for this centre.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) navigator.pop();
                      debugPrint('Error fetching session history: $e');
                    }
                  },
                  icon: Icon(Icons.history, size: 22 * scale),
                  label: Text(
                    "Answer Upload Details",
                    style: TextStyle(
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: 14 * scale,
                      horizontal: 16 * scale,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              // SizedBox(height: 12 * scale),

              // SizedBox(
              //   width: double.infinity,
              //   child: ElevatedButton.icon(
              //     onPressed: () {
              //       Navigator.push(
              //         context,
              //         MaterialPageRoute(
              //           builder: (context) => ExpressInterestPage(
              //             supervisorId: widget.supervisorId,
              //             fullName: _fullName,
              //             centre: _centre,
              //           ),
              //         ),
              //       );
              //     },
              //     icon: Icon(Icons.book, size: 22 * scale),
              //     label: Text(
              //       "Express Interest",
              //       style: TextStyle(
              //         fontSize: 16 * scale,
              //         fontWeight: FontWeight.bold,
              //       ),
              //     ),
              //     style: ElevatedButton.styleFrom(
              //       backgroundColor: const Color.fromARGB(255, 68, 76, 231),
              //       foregroundColor: Colors.white,
              //       padding: EdgeInsets.symmetric(
              //         vertical: 14 * scale,
              //         horizontal: 16 * scale,
              //       ),
              //       shape: RoundedRectangleBorder(
              //         borderRadius: BorderRadius.circular(12),
              //       ),
              //       elevation: 0,
              //     ),
              //   ),
              // ),
              // SizedBox(height: 12 * scale),

              // // Allocation Notification Button
              // SizedBox(
              //   width: double.infinity,
              //   child: ElevatedButton.icon(
              //     onPressed: () {
              //       Navigator.push(
              //         context,
              //         MaterialPageRoute(
              //           builder: (context) => AllocationNotificationPage(
              //             supervisorId: widget.supervisorId,
              //             fullName: _fullName,
              //             centre: _centre,
              //           ),
              //         ),
              //       );
              //     },
              //     icon: Icon(Icons.notifications_outlined, size: 22 * scale),
              //     label: Text(
              //       "Allocation Notification",
              //       style: TextStyle(
              //         fontSize: 16 * scale,
              //         fontWeight: FontWeight.bold,
              //       ),
              //     ),
              //     style: ElevatedButton.styleFrom(
              //       backgroundColor: const Color.fromARGB(255, 68, 76, 231),
              //       foregroundColor: Colors.white,
              //       padding: EdgeInsets.symmetric(
              //         vertical: 14 * scale,
              //         horizontal: 16 * scale,
              //       ),
              //       shape: RoundedRectangleBorder(
              //         borderRadius: BorderRadius.circular(12),
              //       ),
              //       elevation: 0,
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppFooter(),
    );
  }

  // Helper method to build info rows
  Widget _buildInfoRow(String label, String value, double scale) {
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

  /// Fetches or auto-generates the active Super Proctor Code for the current exam session.
  /// Pre-condition: Only generates/displays for "Super Proctor", never for "Invigilator" or "BITS observer".
  Future<void> _fetchActiveSuperProctorCode() async {
    try {
      final effectiveType = _invigilatorType.isNotEmpty
          ? _invigilatorType
          : widget.invigilatorType;

      // 1. Role validation check: Only proceed for Super Proctor
      if (!SuperProctorService.isSuperProctor(effectiveType)) {
        if (mounted) {
          setState(() {
            _superProctorCode = null;
            _isLoadingSuperProctorCode = false;
          });
        }
        return;
      }

      final effectiveCentre = _centre.isNotEmpty ? _centre : widget.centre;
      if (effectiveCentre.isEmpty) return;

      if (mounted && _superProctorCode == null) {
        setState(() {
          _isLoadingSuperProctorCode = true;
        });
      }

      // 2. Fetch existing or auto-generate code with GPS & submit to DynamoDB
      final code = await SuperProctorService()
          .getOrAutoGenerateSuperProctorCode(
            supervisorId: widget.supervisorId,
            centre: effectiveCentre,
            invigilatorType: effectiveType,
          );

      if (mounted) {
        setState(() {
          _superProctorCode = code;
          _isLoadingSuperProctorCode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSuperProctorCode = false;
        });
      }
      debugPrint(
        '[HomePage] Error loading/generating active super proctor code: $e',
      );
    }
  }

  /// Builds a smooth loading placeholder widget while Super Proctor Code is generating
  Widget _buildSuperProctorLoading(BuildContext context, double scale) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 12 * scale,
      ),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 120, 130, 235).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color.fromARGB(
            255,
            120,
            130,
            235,
          ).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18 * scale,
            height: 18 * scale,
            child: const CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Color.fromARGB(255, 68, 76, 231),
              ),
            ),
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Text(
              "Generating Super Proctor Code...",
              style: TextStyle(
                fontSize: 13 * scale,
                fontWeight: FontWeight.w600,
                color: const Color.fromARGB(255, 68, 76, 231),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a prominent Super Proctor Code display widget with copy button on HomePage
  Widget _buildSuperProctorDisplay(BuildContext context, double scale) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 10 * scale,
      ),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 120, 130, 235).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color.fromARGB(
            255,
            120,
            130,
            235,
          ).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6 * scale),
            decoration: const BoxDecoration(
              color: Color.fromARGB(255, 68, 76, 231),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.vpn_key_rounded,
              color: Colors.white,
              size: 16 * scale,
            ),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Super Proctor Code",
                  style: TextStyle(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w600,
                    color: const Color.fromARGB(255, 68, 76, 231),
                  ),
                ),
                SizedBox(height: 2 * scale),
                SelectableText(
                  _superProctorCode ?? '',
                  style: TextStyle(
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy_rounded, size: 20 * scale),
            color: const Color.fromARGB(255, 68, 76, 231),
            tooltip: 'Copy Code',
            onPressed: () {
              if (_superProctorCode != null) {
                Clipboard.setData(ClipboardData(text: _superProctorCode!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Super Proctor Code copied to clipboard!"),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
