import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:supervisorapp/pages/homepage.dart';
import 'package:supervisorapp/Services/StorageService.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supervisorapp/Services/LoginFlowService.dart';
import 'package:supervisorapp/Services/auth/supervisor_auth_service.dart';
import 'package:supervisorapp/pages/register.dart';
import 'package:supervisorapp/Services/logging/supervisor_audit_log_service.dart';

class Login extends StatefulWidget {
  final Map<String, dynamic>? activeExam;

  const Login({super.key, this.activeExam});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final StorageService _storageService = StorageService();
  final LoginFlowService _loginFlowService = LoginFlowService();
  final DynamoDBService _dynamoDBService = DynamoDBService();
  bool _isLoading = true;
  String? _supervisorId;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _activeExam;
  bool _isLoggingIn = false;

  bool get _hasLocalData => _supervisorId != null && _userData != null;

  @override
  void initState() {
    super.initState();
    _loadStoredData();
  }

  @override
  void dispose() {
    _storageService.dispose();
    _loginFlowService.dispose();
    super.dispose();
  }

  /// Load stored supervisor data from local storage
  Future<void> _loadStoredData() async {
    try {
      final prefs = SharedPreferencesAsync();
      final storedSupervisorId = await prefs.getString('current_supervisor_id');
      final now = DateTime.now();
      final todayStr = DateFormat('dd-MM-yyyy').format(now);

      if (storedSupervisorId == null) {
        if (mounted) {
          setState(() {
            _supervisorId = null;
            _userData = null;
            _activeExam = null;
            _isLoading = false;
          });
        }
        return;
      }

      // 1. FAST BYPASS: If we already authenticated today and the window hasn't expired
      final localSessionJson = await prefs.getString('active_session_info');
      final userData = await _storageService.getLocalRegistrationData(
        storedSupervisorId,
      );

      if (localSessionJson != null && userData != null) {
        try {
          final Map<String, dynamic> session = jsonDecode(localSessionJson);
          final String sessionDate = session['date'];
          final String sessionName = session['session'];

          // Check if the session was explicitly marked as finished
          final bool isMarked = await _storageService.isSessionMarked(
            storedSupervisorId,
            sessionDate,
            sessionName,
          );

          if (sessionDate == todayStr && isMarked) {
            final DateTime end = DateTime.parse(session['endTime']);
            if (now.isBefore(end)) {
              print(
                ' [Login] Success: Active authenticated session found. Bypassing to Home.',
              );

              try {
                final liveResult = await _dynamoDBService.getSupervisorDetails(
                  storedSupervisorId,
                );
                if (liveResult['success'] == true) {
                  final d = liveResult['data'] as Map<String, dynamic>;
                  final liveCenter = d['centre'] ?? d['Exam hall'];
                  final liveName = d['name'] ?? d['Name'] ?? d['full_name'];
                  final liveType =
                      d['type'] ?? d['Type'] ?? d['invigilator_type'];
                  if (liveCenter != null &&
                      liveCenter.toString().trim().isNotEmpty) {
                    userData['centre'] = liveCenter.toString().trim();
                  }
                  if (liveName != null &&
                      liveName.toString().trim().isNotEmpty) {
                    userData['full_name'] = liveName.toString().trim();
                    userData['name'] = liveName.toString().trim();
                  }
                  if (liveType != null &&
                      liveType.toString().trim().isNotEmpty) {
                    userData['invigilator_type'] = liveType.toString().trim();
                    userData['type'] = liveType.toString().trim();
                  }
                  print(
                    ' [Login] Bypass: Live profile synced → Name: ${userData['full_name']}, Centre: ${userData['centre']}',
                  );
                }
              } catch (e) {
                print(' [Login] Bypass: Could not sync live data: $e');
                // Continue with cached data if network fails
              }
              // ─────────────────────────────────────────────────────────────

              await _loginFlowService.persistSessionData(
                supervisorId: storedSupervisorId,
                activeExam: {
                  'date': sessionDate,
                  'session': sessionName,
                  'allowedStartTime': session['allowedStartTime'],
                  'parsedEndTime': session['endTime'],
                },
                sessionSource: sessionName,
              );

              S3LogService.logAttendance(
                supervisorId: storedSupervisorId,
                action: 'SESSION_BYPASS',
                status: 'SUCCESS',
                examDate: sessionDate,
                session: sessionName,
              );

              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => HomePage(
                      supervisorId:
                          userData['supervisor_id'] ?? storedSupervisorId,
                      fullName:
                          (userData['full_name'] ?? userData['name']) ??
                          'Unknown',
                      centre: userData['centre'] ?? 'Unknown',
                      invigilatorType:
                          userData['invigilator_type'] ?? 'Unknown',
                    ),
                  ),
                );
              }
              return;
            }
          }
        } catch (e) {
          print(' [Login] Bypass parsing error: $e');
        }
      }

      // 2. NORMAL LOADING: Display cached profile INSTANTLY (0ms delay)
      if (userData != null) {
        if (mounted) {
          setState(() {
            _supervisorId = storedSupervisorId;
            _userData = userData;
            _isLoading =
                false; // Show UI immediately without waiting for network!
          });
        }

        // Fetch active exam and live details asynchronously in background without blocking UI
        _storageService.getCurrentActiveExam(userData['centre'] ?? 'Unknown').then((
          exam,
        ) async {
          if (mounted && exam != null) {
            setState(() => _activeExam = exam);

            // Check if THIS specific active exam is already marked
            final isAlreadyMarked = await _storageService.isSessionMarked(
              storedSupervisorId,
              exam['date'],
              exam['session'],
            );

            if (isAlreadyMarked) {
              debugPrint(
                ' [Login] Session ${exam['session']} already marked for today. Bypassing to Home.',
              );

              try {
                final prefs = SharedPreferencesAsync();
                await prefs.setString(
                  'registration_$storedSupervisorId',
                  jsonEncode(userData),
                );
              } catch (_) {}

              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => HomePage(
                      supervisorId:
                          userData['supervisor_id'] ?? storedSupervisorId,
                      fullName:
                          (userData['full_name'] ?? userData['name']) ??
                          'Unknown',
                      centre: userData['centre'] ?? 'Unknown',
                      invigilatorType:
                          userData['invigilator_type'] ?? 'Unknown',
                    ),
                  ),
                );
              }
            }
          }
        });

        _dynamoDBService.getSupervisorDetails(storedSupervisorId).then((
          liveResult,
        ) {
          if (liveResult['success'] == true && mounted) {
            final d = liveResult['data'] as Map<String, dynamic>;
            final liveCenter = d['centre'] ?? d['Exam hall'];
            final liveName = d['name'] ?? d['Name'] ?? d['full_name'];
            final liveType = d['type'] ?? d['Type'] ?? d['invigilator_type'];
            bool changed = false;
            if (liveCenter != null &&
                liveCenter.toString().trim().isNotEmpty &&
                userData['centre'] != liveCenter.toString().trim()) {
              userData['centre'] = liveCenter.toString().trim();
              changed = true;
            }
            if (liveName != null &&
                liveName.toString().trim().isNotEmpty &&
                userData['full_name'] != liveName.toString().trim()) {
              userData['full_name'] = liveName.toString().trim();
              userData['name'] = liveName.toString().trim();
              userData['Name'] = liveName.toString().trim();
              changed = true;
            }
            if (liveType != null &&
                liveType.toString().trim().isNotEmpty &&
                userData['invigilator_type'] != liveType.toString().trim()) {
              userData['invigilator_type'] = liveType.toString().trim();
              userData['type'] = liveType.toString().trim();
              changed = true;
            }
            if (changed && mounted) {
              setState(() => _userData = Map<String, dynamic>.from(userData));
            }
          }
        });

        Map<String, dynamic>? activeExam = widget.activeExam;
        if (activeExam == null) {
          activeExam = await _storageService.getCurrentActiveExam(
            userData['centre'] ?? 'Unknown',
          );
        }
        if (mounted) {
          setState(() {
            _activeExam = activeExam;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _supervisorId = null;
          _userData = null;
          _activeExam = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint(' [Login] Error loading stored data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAutoLogin() async {
    if (_supervisorId == null || _userData == null) return;

    setState(() {
      _isLoggingIn = true;
    });

    try {
      await _loginFlowService.performLoginFlow(
        context: context,
        supervisorId: _supervisorId!,
        userData: _userData!,
        initialActiveExam: _activeExam,
        silentLocationCheck: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    }
  }

  void _showClearDataConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Register New User'),
          content: const Text(
            'Proceeding will remove the current supervisor account from this device.\n\nAre you sure you want to register a new user?',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                nav.pop(); // Close dialog

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) =>
                      const Center(child: CircularProgressIndicator()),
                );

                await _storageService.clearAllRegistrationData();

                if (mounted) {
                  nav.pop(); // Remove loading dialog
                  await nav.push(
                    MaterialPageRoute(builder: (context) => const Register()),
                  );
                  _loadStoredData();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Remove & Register'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // Removed back button
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
                'Supervisor App - BITS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Color.fromARGB(255, 68, 76, 231),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Fetching details...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Welcome to Supervisor Attendance Manager",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'RobotoMono',
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _hasLocalData
                            ? "Welcome back! Please login to continue."
                            : "Please register if this is your first time. If you have already registered, proceed to login.",
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: 'RobotoMono',
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Register Button
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (_hasLocalData) {
                              _showClearDataConfirmation();
                            } else {
                              // Navigate to register and wait for return
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const Register(),
                                ),
                              );
                              // Refresh the local data check when returning
                              _loadStoredData();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(
                              255,
                              68,
                              76,
                              231,
                            ),
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            "Register",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Login Button - Disabled if no local data or logging in
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: (_hasLocalData && !_isLoggingIn)
                              ? () => _handleAutoLogin()
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (_hasLocalData && !_isLoggingIn)
                                ? const Color.fromARGB(255, 68, 76, 231)
                                : Colors.grey.shade400,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade500,
                          ),
                          child: _isLoggingIn
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  "Login",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      // Show hint if login is disabled
                      if (!_hasLocalData) ...[
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            "Please register first to enable login.",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: const AppFooter(),
    );
  }
}
