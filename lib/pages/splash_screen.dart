import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:supervisorapp/pages/login.dart';
import 'package:supervisorapp/pages/homepage.dart';
import 'package:supervisorapp/Services/auth/supervisor_auth_service.dart';
import 'package:supervisorapp/Services/StorageService.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  final DynamoDBService _dynamoDBService = DynamoDBService();
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
    Timer(const Duration(seconds: 2), () => _initRouting());
  }

  @override
  void dispose() {
    _controller.dispose();
    _storageService.dispose();
    _dynamoDBService.dispose();
    super.dispose();
  }

  Future<void> _initRouting() async {
    try {
      final prefs = SharedPreferencesAsync();
      final supervisorId = await prefs.getString('current_supervisor_id');
      if (supervisorId == null) {
        _navigateTo(const Login());
        return;
      }

      final now = DateTime.now();
      final todayStr = DateFormat('dd-MM-yyyy').format(now);

      // 1. PRIORITY BYPASS: If we have an active authenticated session for TODAY
      final localSessionJson = await prefs.getString('active_session_info');
      if (localSessionJson != null) {
        try {
          final Map<String, dynamic> session = jsonDecode(localSessionJson);
          final String sessionDate = session['date'];
          final String sessionName = session['session'];

          print(
            ' [Splash] Persistence Check: Found cached session $sessionName for date $sessionDate',
          );

          // Check if this specific session was marked as finished
          final bool isMarked = await _storageService.isSessionMarked(
            supervisorId,
            sessionDate,
            sessionName,
          );

          print(' [Splash] Persistence Check: isMarked = $isMarked');

          if (sessionDate == todayStr && isMarked) {
            final DateTime end = DateTime.parse(session['endTime']);
            final String? storedStart = await prefs.getString(
              'current_session_start',
            );
            final String? storedEnd = await prefs.getString(
              'current_session_end',
            );

            debugPrint('-----------------------------------------');
            debugPrint(' [Splash] Persistence Check for session $sessionName');
            debugPrint(' [Local Storage] START TIME: $storedStart');
            debugPrint(' [Local Storage] END TIME:   $storedEnd');
            debugPrint(' [Splash] CURRENT TIME:      ${now.toIso8601String()}');

            // Safety check for ISO format to avoid FormatException
            if (session['endTime'] != null &&
                !session['endTime'].contains('T')) {
              print(
                ' [Splash] Legacy endTime format detected. Ignoring bypass.',
              );
              return;
            }

            bool isWithinWindow = now.isBefore(end);
            if (storedEnd != null) {
              if (!storedEnd.contains('T')) {
                print(
                  ' [Splash] Legacy storedEnd format detected. Ignoring bypass.',
                );
                return;
              }
              final DateTime et = DateTime.parse(storedEnd);
              isWithinWindow = now.isBefore(et);
            }

            debugPrint(' [Splash] IS WITHIN DURATION: $isWithinWindow');
            debugPrint('-----------------------------------------');

            if (isWithinWindow) {
              final userData = await _storageService.getLocalRegistrationData(
                supervisorId,
              );
              if (userData != null) {
                try {
                  final liveResult = await _dynamoDBService
                      .getSupervisorDetails(supervisorId);
                  if (liveResult['success'] == true) {
                    final d = liveResult['data'] as Map<String, dynamic>;
                    if (d['centre'] != null) {
                      userData['centre'] = d['centre'].toString();
                    }
                    if (d['name'] != null) {
                      userData['full_name'] = d['name'].toString();
                    }
                    if (d['type'] != null) {
                      userData['invigilator_type'] = d['type'].toString();
                    }
                    await prefs.setString(
                      'registration_$supervisorId',
                      jsonEncode(userData),
                    );
                    print(
                      ' [Splash] Live centre synced → ${userData['centre']}',
                    );
                  }
                } catch (e) {
                  print(' [Splash] Could not sync live data: $e');
                }

                print(
                  ' [Splash] SUCCESS: Auto-logging into Homepage for session "$sessionName".',
                );
                _navigateTo(
                  HomePage(
                    supervisorId: supervisorId,
                    fullName:
                        (userData['full_name'] ?? userData['name']) ??
                        'Supervisor',
                    centre: userData['centre'] ?? 'Unknown',
                    invigilatorType: userData['invigilator_type'] ?? 'Unknown',
                  ),
                );
                return;
              }
            } else {
              print(' [Splash] SESSION EXPIRED: Redirecting to Login.');
            }
          }
        } catch (e) {
          print(' [Splash] Bypass check error: $e');
        }
      }

      // 2. FETCH LIVE SESSIONS: Check if there's any active exam to login for
      //    First try DynamoDB; if offline, fall back to locally cached timings.
      Map<String, String>? timings;
      String? centre;

      final supervisorResult = await _dynamoDBService.getSupervisorDetails(
        supervisorId,
      );
      if (supervisorResult['success'] == true) {
        centre = supervisorResult['data']['centre'] ?? 'Unknown';

        final timingResult = await _dynamoDBService.getCenterTimings(centre!);
        if (timingResult['success'] == true && timingResult['data'] != null) {
          timings = Map<String, String>.from(timingResult['data']);

          // ✅ Cache timings locally so the app works offline next time
          await prefs.setString(
            'cached_center_timings',
            jsonEncode({
              'centre': centre,
              'date': todayStr,
              'timings': timings,
            }),
          );
          print(' [Splash] Exam timings cached locally for $centre');
        }
      }

      // 🔄 Fallback: use locally cached timings if live fetch failed
      if (timings == null) {
        final cachedJson = await prefs.getString('cached_center_timings');
        if (cachedJson != null) {
          try {
            final cached = jsonDecode(cachedJson);
            // Use cached timings only if they are from today (same date)
            if (cached['date'] == todayStr) {
              timings = Map<String, String>.from(cached['timings']);
              centre = cached['centre'];
              print(
                ' [Splash] Using cached exam timings for $centre (offline fallback)',
              );
            }
          } catch (e) {
            print(' [Splash] Failed to parse cached timings: $e');
          }
        }
      }

      if (timings != null) {
        Map<String, dynamic>? activeExam;

        for (String sessionType in ['FN', 'AN', 'EN']) {
          try {
            final startStr = timings['${sessionType}_start'];
            final endStr = timings['${sessionType}_end'];
            if (startStr == null || startStr.isEmpty) continue;

            final stParts = startStr.split(':');
            final etParts = (endStr ?? '23:59').split(':');
            final st = DateTime(
              now.year,
              now.month,
              now.day,
              int.parse(stParts[0]),
              int.parse(stParts[1]),
            );
            final et = DateTime(
              now.year,
              now.month,
              now.day,
              int.parse(etParts[0]),
              int.parse(etParts[1]),
            );
            final bufferStart = st.subtract(const Duration(minutes: 30));

            if (now.isAfter(bufferStart) && now.isBefore(et)) {
              activeExam = {
                'date': todayStr,
                'session': sessionType,
                'examStartTime': startStr,
                'examEndTime': endStr,
                'allowedStartTime': bufferStart.toIso8601String(),
                'parsedEndTime': et.toIso8601String(),
              };
              break;
            }
          } catch (e) {}
        }

        if (activeExam != null) {
          _navigateTo(Login(activeExam: activeExam));
          return;
        }
      }

      _navigateTo(const Login());
    } catch (e) {
      _navigateTo(const Login());
    }
  }

  void _navigateTo(Widget page) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, anim, secAnim) => page,
        transitionsBuilder: (context, anim, secAnim, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Image.asset('assets/images/company_logo.png'),
                ),
              ),

              const SizedBox(height: 50),
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF444CE7)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
