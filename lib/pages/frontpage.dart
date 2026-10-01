import 'package:flutter/material.dart';
import 'package:supervisorapp/Services/LoginFlowService.dart';
import 'package:supervisorapp/Services/StorageService.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supervisorapp/pages/register.dart';

class FrontPage extends StatefulWidget {
  const FrontPage({super.key});

  @override
  State<FrontPage> createState() => _FrontPageState();
}

class _FrontPageState extends State<FrontPage> {
  final StorageService _storageService = StorageService();
  final LoginFlowService _loginFlowService = LoginFlowService();

  bool _hasLocalData = false;
  bool _isChecking = true;

  String? _supervisorId;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _activeExam; 

  @override
  void initState() {
    super.initState();
    _checkForLocalData();
  }

  /// Check if there's any registration data in local storage
  Future<void> _checkForLocalData() async {
    try {
      final prefs = SharedPreferencesAsync();
      final keys = await prefs.getKeys();

      final storedSupervisorId = await prefs.getString('current_supervisor_id');
      final hasRegistration = keys.any(
        (key) => key.startsWith('registration_'),
      );

      setState(() {
        _hasLocalData = hasRegistration;
        _supervisorId = storedSupervisorId;
        _isChecking = false;
      });

      if (storedSupervisorId != null) {
        _userData = await _storageService.getLocalRegistrationData(storedSupervisorId);
        if (_userData != null) {
          _activeExam = await _storageService.getCurrentActiveExam(_userData!['centre'] ?? 'Unknown');
        }
      }

      print(' Local data check: ${hasRegistration ? "Found" : "Not found"}');
    } catch (e) {
      print(' Error checking local data: $e');
      setState(() {
        _hasLocalData = false;
        _isChecking = false;
      });
    }
  }

  @override
  void dispose() {
    _storageService.dispose();
    _loginFlowService.dispose();
    super.dispose();
  }

  Future<void> _handleAutoLogin() async {
    if (_supervisorId == null || _userData == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Account Not Found'),
          content: const Text('No registration record was found on this device. Please register first.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    await _loginFlowService.performLoginFlow(
      context: context,
      supervisorId: _supervisorId!,
      userData: _userData!,
      initialActiveExam: _activeExam,
    );
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

                if (!mounted) return;
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) =>
                      const Center(child: CircularProgressIndicator()),
                );

                await _storageService.clearAllRegistrationData();

                if (!mounted) return;
                nav.pop(); // Remove loading
                await nav.push(
                  MaterialPageRoute(builder: (context) => const Register()),
                );
                if (mounted) {
                  _checkForLocalData();
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
        automaticallyImplyLeading: false,
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
            SizedBox(width: 12),
            Expanded(
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome to Supervisor Attendance Manager",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'RobotoMono',
                  ),
                ),
                SizedBox(height: 20),
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
                SizedBox(height: 40),

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
                        _checkForLocalData();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      "Register",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Login Button - Disabled if no local data
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () => _handleAutoLogin(),// Disabled if no local data
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasLocalData
                          ? Color.fromARGB(255, 68, 76, 231)
                          : Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade500,
                    ),
                    child: _isChecking
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            "Login",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                // Show hint if login is disabled
                if (!_isChecking && !_hasLocalData) ...[
                  SizedBox(height: 12),
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
