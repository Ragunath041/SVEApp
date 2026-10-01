// ignore_for_file: file_names

import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supervisorapp/pages/homepage.dart';
import 'package:supervisorapp/Services/StorageService.dart';
import 'package:supervisorapp/Services/FaceRecognitionService.dart';
import 'package:supervisorapp/Services/attendance/supervisor_attendance_service.dart';
import 'package:supervisorapp/Services/auth/supervisor_auth_service.dart';
import 'package:supervisorapp/pages/face_camera_page.dart';
import 'package:supervisorapp/pages/face_capture_guide_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'AWSClockSyncService.dart';
import 'package:supervisorapp/Services/logging/supervisor_audit_log_service.dart';

class LoginFlowService {
  final StorageService _storageService = StorageService();
  final AttendanceService _attendanceService = AttendanceService();
  final DynamoDBService _dynamoDBService = DynamoDBService();

  /// Unified method to persist session timings locally
  Future<void> persistSessionData({
    required String supervisorId,
    required Map<String, dynamic>? activeExam,
    required String sessionSource,
  }) async {
    try {
      final prefs = SharedPreferencesAsync();
      final now = DateTime.now();
      final dateStr = activeExam != null
          ? activeExam['date']
          : DateFormat('dd-MM-yyyy').format(now);
      final session = activeExam != null
          ? activeExam['session'].toString().trim()
          : sessionSource;

      debugPrint(
        ' [Persistence] Saving: $session for $dateStr (Source: $sessionSource)',
      );

      // 1. Mark session as finished bit
      await _storageService.markSessionAsFinished(
        supervisorId,
        dateStr,
        session,
      );

      // 2. Store session windows if valid exam found
      if (activeExam != null) {
        String? startTime =
            activeExam['allowedStartTime'] ?? activeExam['examStartTime'];
        String? endTime =
            activeExam['parsedEndTime'] ?? activeExam['examEndTime'];

        // Robust conversion of raw 'HH:mm' to ISO8601 if needed
        if (startTime != null && !startTime.contains('T')) {
          final parts = startTime.split(':');
          startTime = DateTime(
            now.year,
            now.month,
            now.day,
            int.parse(parts[0]),
            int.parse(parts[1]),
          ).toIso8601String();
        }
        if (endTime != null && !endTime.contains('T')) {
          final parts = endTime.split(':');
          endTime = DateTime(
            now.year,
            now.month,
            now.day,
            int.parse(parts[0]),
            int.parse(parts[1]),
          ).toIso8601String();
        }

        if (startTime != null && endTime != null) {
          await prefs.setString(
            'active_session_info',
            jsonEncode({
              'date': dateStr,
              'session': session,
              'allowedStartTime': startTime,
              'endTime': endTime,
            }),
          );

          await _storageService.saveCurrentSessionWindow(
            startTime: startTime,
            endTime: endTime,
          );

          debugPrint('=========================================');
          debugPrint(' [PERSISTENCE SAVED SUCCESSFULLY]');
          debugPrint(' SESSION: $session');
          debugPrint(' END TIME: $endTime');
          debugPrint('=========================================');
        }
      }
    } catch (e) {
      debugPrint(' !!! PERSISTENCE ERROR: $e');
    }
  }

  /// Unified Login Flow
  Future<void> performLoginFlow({
    required BuildContext context,
    required String supervisorId,
    required Map<String, dynamic> userData,
    Map<String, dynamic>? initialActiveExam,
    bool silentLocationCheck = false,
  }) async {
    String centre =
        (userData['centre'] ?? userData['Exam hall'])?.toString() ?? 'Unknown';
    String fullName =
        (userData['full_name'] ?? userData['name'] ?? userData['Name'])
            ?.toString() ??
        '';
    String email = userData['email']?.toString() ?? 'Unknown';
    String invigilatorType =
        (userData['invigilator_type'] ?? userData['type'] ?? userData['Type'])
            ?.toString() ??
        'Unknown';

    // 1. Kick off location fetch & supervisor details fetch concurrently in the background!
    // They will resolve in parallel while the user is viewing the guide and capturing face.
    final locationFuture = _attendanceService.getCurrentLocation();
    final detailsFuture = _dynamoDBService.getSupervisorDetails(supervisorId);

    // 2. NAVIGATE TO FACE CAPTURE GUIDE PAGE IMMEDIATELY (ZERO DELAY!)
    final XFile? faceImage = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceCaptureGuidePage(
          title: 'Face Login Guide',
          nextPage: FaceCameraPage(
            title: 'Face Login',
            instructionText: 'Look Straight to Verify',
            supervisorId: supervisorId,
            autoCapture: true, // Use auto-capture for consistent experience
          ),
        ),
      ),
    );

    if (faceImage == null || !context.mounted) {
      // User cancelled face capture
      return;
    }

    // 3. User captured face: Run Face Verification
    _showLoading(context, 'Verifying face...');
    bool isVerified = false;
    double simScore = -1.0;
    String? faceError;
    try {
      final storedEmbedding =
          await FaceRecognitionServiceEnhanced.loadEmbedding(supervisorId);
      if (storedEmbedding != null) {
        final capturedEmbedding =
            await FaceRecognitionServiceEnhanced.generateEmbedding(
              faceImage.path,
            );
        if (capturedEmbedding != null) {
          final similarity = FaceRecognitionServiceEnhanced.compareFaces(
            storedEmbedding,
            capturedEmbedding,
          );
          simScore = similarity;
          debugPrint(
            ' [Login] Face Similarity Score: ${similarity.toStringAsFixed(4)} (Required: 0.88)',
          );
          isVerified = similarity >= 0.88;
        } else {
          faceError = 'Failed to generate embedding from captured face';
        }
      } else {
        faceError = 'No stored face embedding found';
        debugPrint(
          ' [Login] Error: No stored face embedding found for $supervisorId',
        );
      }
    } catch (e) {
      faceError = e.toString();
      debugPrint('Face error: $e');
    }
    if (context.mounted) Navigator.pop(context);

    if (!isVerified) {
      double logLat = 0.0;
      double logLong = 0.0;
      try {
        final locRes = await locationFuture;
        logLat = (locRes['latitude'] as num?)?.toDouble() ?? 0.0;
        logLong = (locRes['longitude'] as num?)?.toDouble() ?? 0.0;
      } catch (e) {
        debugPrint('LoginFlowService: Error getting location for failed login log: $e');
      }

      S3LogService.logAttendance(
        supervisorId: supervisorId,
        action: 'LOGIN',
        status: 'FAILED',
        centre: centre,
        errorMessage: faceError ?? 'Face verification similarity too low',
        gpsLatitude: logLat != 0.0 ? logLat.toString() : '',
        gpsLongitude: logLong != 0.0 ? logLong.toString() : '',
        verificationScore: simScore >= 0 ? simScore.toStringAsFixed(4) : '',
      );
      if (context.mounted) {
        if (faceError != null &&
            faceError.contains('Spectacle glare detected')) {
          _showError(
            context,
            'Spectacle glare detected! Please tilt your head slightly away from the light and try again.',
          );
        } else {
          _showError(context, 'Face verification failed. Please try again.');
        }
      }
      return;
    }

    if (!context.mounted) return;

    // 4. Await location & live profile details (already finished in parallel!)
    _showLoading(context, 'Validating location...');
    final locationResult = await locationFuture;

    try {
      final detailsResult = await detailsFuture;
      if (detailsResult['success'] == true) {
        final data = detailsResult['data'] ?? {};
        final liveCentre = data['centre'] ?? data['Exam hall'];
        if (liveCentre != null && liveCentre.toString().trim().isNotEmpty) {
          centre = liveCentre.toString().trim();
        }
        final liveName = data['name'] ?? data['full_name'] ?? data['Name'];
        if (liveName != null && liveName.toString().trim().isNotEmpty) {
          fullName = liveName.toString().trim();
        }
        final liveType =
            data['type'] ?? data['invigilator_type'] ?? data['Type'];
        if (liveType != null && liveType.toString().trim().isNotEmpty) {
          invigilatorType = liveType.toString().trim();
        }
        debugPrint(
          ' [LoginFlow] Live profile synced from DynamoDB → name: $fullName, centre: $centre, type: $invigilatorType',
        );
      }
    } catch (e) {
      debugPrint(' [LoginFlow] detailsFuture error: $e');
    }

    if (locationResult['success'] != true) {
      if (context.mounted) Navigator.pop(context);
      S3LogService.logAttendance(
        supervisorId: supervisorId,
        action: 'LOGIN',
        status: 'FAILED',
        centre: centre,
        errorMessage:
            'Location check failed: ${locationResult['error'] ?? 'Unknown location error'}',
      );
      if (context.mounted) {
        _showError(
          context,
          locationResult['error'] ?? 'Unable to get location',
        );
      }
      return;
    }

    final double lat = (locationResult['latitude'] as num?)?.toDouble() ?? 0.0;
    final double long =
        (locationResult['longitude'] as num?)?.toDouble() ?? 0.0;

    // Step 5: Location Bounds Check
    final validationResult = await _attendanceService.validateLocationForCentre(
      centreName: centre,
      currentLatitude: lat,
      currentLongitude: long,
    );
    if (context.mounted) Navigator.pop(context);

    if (validationResult['success'] != true) {
      final String errorMessage =
          validationResult['error'] ??
          "You are not within the boundaries of $centre.";
      S3LogService.logAttendance(
        supervisorId: supervisorId,
        action: 'LOGIN',
        status: 'FAILED',
        centre: centre,
        errorMessage: errorMessage,
        gpsLatitude: lat.toString(),
        gpsLongitude: long.toString(),
        verificationScore: simScore >= 0 ? simScore.toStringAsFixed(4) : '',
      );
      if (context.mounted) {
        if (AWSClockSyncService.isLikelyDeviceTimeIssue(errorMessage)) {
          AWSClockSyncService.handlePossibleTimeIssue(context, errorMessage);
        } else {
          _showError(context, errorMessage);
        }
      }
      return;
    }

    // Step 5: Final Persistence & Attendance
    Map<String, dynamic>? activeExam =
        initialActiveExam ?? await _storageService.getCurrentActiveExam(centre);

    // ENSURE we have timings! If cache failed, try to reach out?
    // We already checked in SplashScreen, but just in case:
    if (activeExam == null) {
      debugPrint(
        ' [Flow] No active exam in cache, trying last-resort fetch...',
      );
      final timingResult = await _dynamoDBService.getCenterTimings(centre);
      if (timingResult['success'] && timingResult['data'] != null) {
        final now = DateTime.now();
        final timings = Map<String, String>.from(timingResult['data']);

        debugPrint(
          ' [Flow] Last-resort check for ${timings.length} timings...',
        );

        for (String s in ['FN', 'AN', 'EN']) {
          final startStr = timings['${s}_start'];
          final endStr = timings['${s}_end'];
          if (startStr == null || startStr.isEmpty) continue;

          try {
            final startParts = startStr.split(':');
            final endParts = (endStr ?? '23:59').split(':');

            final st = DateTime(
              now.year,
              now.month,
              now.day,
              int.parse(startParts[0]),
              int.parse(startParts[1]),
            );
            final et = DateTime(
              now.year,
              now.month,
              now.day,
              int.parse(endParts[0]),
              int.parse(endParts[1]),
            );
            final bufferStart = st.subtract(const Duration(minutes: 30));

            debugPrint(
              ' [Flow] Checking session $s: Window [${bufferStart.toIso8601String()} to ${et.toIso8601String()}]',
            );

            if (now.isAfter(bufferStart) && now.isBefore(et)) {
              activeExam = {
                'date': DateFormat('dd-MM-yyyy').format(now),
                'session': s,
                'examStartTime': startStr,
                'examEndTime': endStr ?? '23:59',
                'allowedStartTime': bufferStart.toIso8601String(),
                'parsedEndTime': et.toIso8601String(),
              };
              debugPrint(' [Flow] MATCHED SESSION: $s');
              break;
            }
          } catch (e) {
            debugPrint(' [Flow] Error parsing session $s: $e');
          }
        }
      }
    }

    await persistSessionData(
      supervisorId: supervisorId,
      activeExam: activeExam,
      sessionSource: 'Manual',
    );

    // Background cloud marking
    _attendanceService.markAttendance(
      supervisorId: supervisorId,
      centre: centre,
      name: fullName,
      email: email,
      invigilatorType: invigilatorType,
      latitude: lat,
      longitude: long,
      type: 'login',
    );

    S3LogService.logAttendance(
      supervisorId: supervisorId,
      action: 'LOGIN',
      status: 'SUCCESS',
      centre: centre,
      examDate: activeExam != null ? activeExam['date'] ?? '' : '',
      session: activeExam != null ? activeExam['session'] ?? '' : '',
      gpsLatitude: lat.toString(),
      gpsLongitude: long.toString(),
      verificationScore: simScore >= 0 ? simScore.toStringAsFixed(4) : '',
    );

    // Final Success Redirect
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            supervisorId: supervisorId,
            fullName: fullName,
            centre: centre,
            invigilatorType: invigilatorType,
          ),
        ),
      );
    }
  }

  void _showLoading(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showError(BuildContext context, String message) {
    final isFaceError = message.contains('Face verification');

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isFaceError ? "Verification Failed" : "Alert",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFaceError
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF444CE7),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isFaceError ? "Try Again" : "OK",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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

  void dispose() {
    _storageService.dispose();
    _attendanceService.dispose();
    _dynamoDBService.dispose();
  }
}
