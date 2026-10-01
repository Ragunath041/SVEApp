import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supervisorapp/pages/homepage.dart';
import 'package:supervisorapp/widgets/footer.dart';

class ActiveSessionPage extends StatefulWidget {
  final String supervisorId;
  final String fullName;
  final String centre;
  final String invigilatorType;
  final Map<String, dynamic> sessionInfo; // active_session_info from prefs

  const ActiveSessionPage({
    super.key,
    required this.supervisorId,
    required this.fullName,
    required this.centre,
    required this.invigilatorType,
    required this.sessionInfo,
  });

  @override
  State<ActiveSessionPage> createState() => _ActiveSessionPageState();
}

class _ActiveSessionPageState extends State<ActiveSessionPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim =
        CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    // Auto-navigate to HomePage after 2 seconds
    _navTimer = Timer(const Duration(seconds: 2), _goToHome);
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _goToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, anim, secAnim) => HomePage(
          supervisorId: widget.supervisorId,
          fullName: widget.fullName,
          centre: widget.centre,
          invigilatorType: widget.invigilatorType,
        ),
        transitionsBuilder: (context, anim, secAnim, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.sessionInfo;
    final date = session['date'] ?? '--';
    final sessionName = session['session'] ?? '--';
    // Parse ISO end time for display
    String endTimeDisplay = '--';
    try {
      final et = DateTime.parse(session['endTime']);
      endTimeDisplay =
          '${et.hour.toString().padLeft(2, '0')}:${et.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      debugPrint('ActiveSessionPage: Error parsing session endTime: $e');
    }
    String startTimeDisplay = '--';
    try {
      final st = DateTime.parse(session['allowedStartTime'])
          .add(const Duration(minutes: 60)); // actual exam start
      startTimeDisplay =
          '${st.hour.toString().padLeft(2, '0')}:${st.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      debugPrint('ActiveSessionPage: Error parsing session allowedStartTime: $e');
    }

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
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Supervisor Attendance Manager',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Check icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.green.shade300, width: 2),
                  ),
                  child: Icon(
                    Icons.verified_rounded,
                    color: Colors.green.shade600,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Session Already Marked',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Welcome back, ${widget.fullName}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 32),

                // Active Exam Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.event_available,
                              color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Active Exam Session',
                            style: TextStyle(
                              color: Colors.blue.shade800,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$date  •  $sessionName session',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Exam time: $startTimeDisplay – $endTimeDisplay',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // Auto-redirect indicator
                Column(
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF444CE7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Redirecting to dashboard...',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const AppFooter(),
    );
  }
}
