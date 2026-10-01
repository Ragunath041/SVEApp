import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_client.dart';
import '../auth/supervisor_auth_service.dart';

/// Data class holding the components and generated Super Proctor Code
class SuperProctorData {
  final String code;
  final String supervisorId;
  final double latitude;
  final double longitude;
  final String latDigit;
  final String longDigit;
  final String displayDate;
  final String dateDigits;
  final String session;
  final String centre;
  final String examStart;
  final String examEnd;
  final bool isExisting;
  final DateTime createdAt;

  SuperProctorData({
    required this.code,
    required this.supervisorId,
    required this.latitude,
    required this.longitude,
    required this.latDigit,
    required this.longDigit,
    required this.displayDate,
    required this.dateDigits,
    required this.session,
    required this.centre,
    this.examStart = '',
    this.examEnd = '',
    this.isExisting = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'superproctor_code': code,
      'center': centre,
      'date': displayDate,
      'exam_start': examStart,
      'exam_end': examEnd,
      'latitude': latitude,
      'longitude': longitude,
      'session': session,
      'supervisorId': supervisorId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory SuperProctorData.fromJson(
    Map<String, dynamic> json, {
    bool isExisting = true,
  }) {
    final code = (json['superproctor_code'] ?? json['code'] ?? '').toString();
    final center = (json['center'] ?? json['centre'] ?? '').toString();
    final supervisorId = (json['supervisorId'] ?? json['supervisor_id'] ?? '')
        .toString();
    final session = (json['session'] ?? '').toString();
    final date = (json['date'] ?? '').toString();
    final examStart = (json['exam_start'] ?? json['examStartTime'] ?? '')
        .toString();
    final examEnd = (json['exam_end'] ?? json['examEndTime'] ?? '').toString();
    final lat = double.tryParse(json['latitude']?.toString() ?? '0') ?? 0.0;
    final lng = double.tryParse(json['longitude']?.toString() ?? '0') ?? 0.0;
    DateTime createdAt = DateTime.now();
    if (json['created_at'] != null) {
      createdAt =
          DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now();
    }

    return SuperProctorData(
      code: code,
      supervisorId: supervisorId,
      latitude: lat,
      longitude: lng,
      latDigit: SuperProctorService.formatCoordForCode(lat),
      longDigit: SuperProctorService.formatCoordForCode(lng),
      displayDate: date,
      dateDigits: date.replaceAll('-', ''),
      session: session,
      centre: center,
      examStart: examStart,
      examEnd: examEnd,
      createdAt: createdAt,
      isExisting: isExisting,
    );
  }
}

class ExamSessionWindow {
  final String session;
  final String startTime;
  final String endTime;
  final int startMinutes;
  final int endMinutes;
  final bool isCurrentlyActive;

  ExamSessionWindow({
    required this.session,
    required this.startTime,
    required this.endTime,
    required this.startMinutes,
    required this.endMinutes,
    required this.isCurrentlyActive,
  });
}

class SuperProctorService {
  final SupervisorAuthService _authService = SupervisorAuthService();

  static String formatCoordForCode(double coord) {
    final fixed = coord.toStringAsFixed(1);
    return fixed.replaceAll('.', '').replaceAll('-', '');
  }

  static String generateCodeString({
    required String supervisorId,
    required double latitude,
    required double longitude,
    required String session,
    DateTime? date,
  }) {
    final cleanId = supervisorId.trim().toUpperCase();
    final latPart = formatCoordForCode(latitude);
    final longPart = formatCoordForCode(longitude);
    final now = date ?? DateTime.now();
    final datePart = DateFormat('ddMMyyyy').format(now);
    final sessionPart = session.trim().toUpperCase();

    // 1. First 2 characters from Supervisor ID (e.g. SP)
    final prefix = cleanId.length >= 2
        ? cleanId.substring(0, 2)
        : cleanId.padRight(2, 'S');

    // 2. Last 2 characters from Session (e.g. FN, AN, EN)
    final suffix = sessionPart.length >= 2
        ? sessionPart.substring(0, 2)
        : sessionPart.padRight(2, 'X');

    // 3. Middle 4 unique/random characters from the entropy components
    final entropyPool = '$cleanId$latPart$longPart$datePart$sessionPart';
    final chars = entropyPool.split('');
    final rng = Random(entropyPool.hashCode);
    chars.shuffle(rng);
    final middle = chars.take(4).join('');

    // Final 8-character unique code: [Prefix 2] + [Middle 4] + [Session 2]
    return '$prefix$middle$suffix';
  }

  /// Parses a time string (e.g. "09:30", "14:00", "02:00 PM", "9:30 AM") to minutes from midnight
  static int? parseTimeToMinutes(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return null;
    final raw = timeStr.trim().toUpperCase();

    final isPM = raw.contains('PM');
    final isAM = raw.contains('AM');

    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(raw);
    if (match == null) return null;

    int hours = int.tryParse(match.group(1)!) ?? 0;
    int minutes = int.tryParse(match.group(2)!) ?? 0;

    if (isPM && hours < 12) hours += 12;
    if (isAM && hours == 12) hours = 0;

    return hours * 60 + minutes;
  }

  /// Checks whether there is an active exam session right now at this centre.
  /// Allowed access window: strictly in between exam start time and exam end time (0-min buffer).
  /// Returns the active ExamSessionWindow if inside an active window, or null if outside.
  Future<ExamSessionWindow?> getActiveExamSession(
    String centre, {
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    final nowMinutes = currentTime.hour * 60 + currentTime.minute;

    final Map<String, List<String>> sessionDefaults = {
      'FN': ['09:30', '12:30'],
      'AN': ['14:00', '17:00'],
      'EN': ['18:00', '21:00'],
    };

    Map<String, String> dbTimings = {};
    if (centre.isNotEmpty) {
      try {
        final result = await _authService.getCenterTimings(centre);
        if (result['success'] == true && result['data'] != null) {
          dbTimings = Map<String, String>.from(result['data']);
        }
      } catch (e) {
        debugPrint(' [SuperProctorService] Error fetching center timings: $e');
      }
    }

    // Strictly active ONLY in between exam start time and exam end time
    for (final s in ['FN', 'AN', 'EN']) {
      final startStr = dbTimings['${s}_start']?.isNotEmpty == true
          ? dbTimings['${s}_start']!
          : sessionDefaults[s]![0];
      final endStr = dbTimings['${s}_end']?.isNotEmpty == true
          ? dbTimings['${s}_end']!
          : sessionDefaults[s]![1];

      final startMin = parseTimeToMinutes(startStr) ?? 0;
      final endMin = parseTimeToMinutes(endStr) ?? 1440;

      // Active strictly in between exam start time and exam end time
      if (nowMinutes >= startMin && nowMinutes <= endMin) {
        return ExamSessionWindow(
          session: s,
          startTime: startStr,
          endTime: endStr,
          startMinutes: startMin,
          endMinutes: endMin,
          isCurrentlyActive: true,
        );
      }
    }

    return null;
  }

  /// Checks whether a given role string matches "Super Proctor"
  static bool isSuperProctor(String? role) {
    if (role == null) return false;
    final clean = role.trim().toLowerCase();
    return clean == 'super proctor' || clean == 'superproctor';
  }

  /// Automatically validates role, checks active exam session, and gets/generates Super Proctor Code.
  /// - ONLY generates and returns code if role is "Super Proctor" (not for Invigilator or BITS Observer).
  /// - Automatically reuses code if already exists in DynamoDB for today's session.
  /// - Automatically generates and saves new code to DynamoDB if it does not exist yet.
  Future<String?> getOrAutoGenerateSuperProctorCode({
    required String supervisorId,
    required String centre,
    required String invigilatorType,
  }) async {
    // 1. Role Pre-condition: Strictly ONLY for Super Proctor
    if (!isSuperProctor(invigilatorType)) {
      return null;
    }

    if (centre.trim().isEmpty || supervisorId.trim().isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final todayDate = DateFormat('dd-MM-yyyy').format(now);

    // 2. Check if an exam is currently active
    final activeSession = await getActiveExamSession(centre.trim(), now: now);
    if (activeSession == null) {
      return null;
    }

    // 3. Check DynamoDB backend directly for existing code for this session
    final existingData = await fetchExistingSuperProctorCode(
      centre: centre.trim(),
      session: activeSession.session,
      date: todayDate,
      supervisorId: supervisorId.trim().toUpperCase(),
    );

    if (existingData != null && existingData.code.isNotEmpty) {
      return existingData.code;
    }

    // 4. If code does not exist yet, auto-generate and submit to DynamoDB
    try {
      final newData = await generateSuperProctorData(
        supervisorId: supervisorId.trim().toUpperCase(),
        centre: centre.trim(),
        sessionWindow: activeSession,
      );

      final submitResult = await submitSuperProctorCode(newData);
      if (submitResult['success'] == true) {
        return newData.code;
      }
    } catch (e) {
      debugPrint('[SuperProctorService] Auto-generation failed: $e');
    }

    return null;
  }

  /// Fetches the currently active code for today's active exam session directly from DynamoDB backend.
  /// Does NOT rely on local storage — DynamoDB is the sole source of truth.
  Future<String?> getActiveExamCode({
    required String centre,
    required String supervisorId,
  }) async {
    final now = DateTime.now();
    final todayDate = DateFormat('dd-MM-yyyy').format(now);

    // 1. Check if an exam is currently active
    final activeSession = await getActiveExamSession(centre, now: now);
    if (activeSession == null) {
      // Clear any legacy local key if present
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_superproctor_code_$supervisorId');
        await prefs.remove('active_superproctor_date_$supervisorId');
        await prefs.remove('active_superproctor_session_$supervisorId');
      } catch (e) {
        debugPrint('SuperProctorService: Error clearing legacy local prefs: $e');
      }
      return null;
    }

    // 2. Clear any legacy local cache so only DynamoDB is trusted
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_superproctor_code_$supervisorId');
    } catch (e) {
      debugPrint('SuperProctorService: Error clearing legacy local code: $e');
    }

    // 3. Check DynamoDB backend directly
    final existingData = await fetchExistingSuperProctorCode(
      centre: centre,
      session: activeSession.session,
      date: todayDate,
      supervisorId: supervisorId,
    );

    if (existingData != null && existingData.code.isNotEmpty) {
      return existingData.code;
    }

    return null;
  }

  /// Returns the configured exam schedule for a centre (useful for error messages)
  Future<Map<String, String>> getCenterSchedule(String centre) async {
    final Map<String, String> schedule = {
      'FN': '09:30 - 12:30',
      'AN': '14:00 - 17:00',
      'EN': '18:00 - 21:00',
    };

    if (centre.isNotEmpty) {
      try {
        final result = await _authService.getCenterTimings(centre);
        if (result['success'] == true && result['data'] != null) {
          final t = Map<String, String>.from(result['data']);
          if (t['FN_start'] != null && t['FN_end'] != null) {
            schedule['FN'] = '${t['FN_start']} - ${t['FN_end']}';
          }
          if (t['AN_start'] != null && t['AN_end'] != null) {
            schedule['AN'] = '${t['AN_start']} - ${t['AN_end']}';
          }
          if (t['EN_start'] != null && t['EN_end'] != null) {
            schedule['EN'] = '${t['EN_start']} - ${t['EN_end']}';
          }
        }
      } catch (e) {
        debugPrint('SuperProctorService: Error getting center timings: $e');
      }
    }
    return schedule;
  }

  /// Checks if a Super Proctor Code was already generated for this centre, session, date, and supervisor
  Future<SuperProctorData?> fetchExistingSuperProctorCode({
    required String centre,
    required String session,
    required String date,
    required String supervisorId,
  }) async {
    try {
      final response = await ApiClient.sendAction(
        action: 'getSuperProctorCode',
        payload: {
          'center': centre,
          'session': session,
          'date': date,
          'supervisorId': supervisorId,
        },
      );

      if (response['success'] == true &&
          response['found'] == true &&
          response['data'] != null) {
        final dataMap = Map<String, dynamic>.from(response['data']);
        return SuperProctorData.fromJson(dataMap, isExisting: true);
      }
    } catch (e) {
      debugPrint(' [SuperProctorService] Error fetching existing code: $e');
    }
    return null;
  }

  /// Obtains current GPS coordinates using Geolocator
  Future<Position> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        'Location services are disabled. Please enable GPS on your device.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception(
          'Location permission was denied. GPS access is required to generate the code.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permissions are permanently denied. Please enable them in device settings.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (e) {
      debugPrint(
        ' [SuperProctorService] High-accuracy GPS timed out ($e), attempting fallback...',
      );
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
    }
  }

  /// Generates full SuperProctorData object for a new code
  Future<SuperProctorData> generateSuperProctorData({
    required String supervisorId,
    required String centre,
    required ExamSessionWindow sessionWindow,
    Position? position,
    DateTime? date,
  }) async {
    final pos = position ?? await getCurrentLocation();
    final now = date ?? DateTime.now();

    final latDigit = formatCoordForCode(pos.latitude);
    final longDigit = formatCoordForCode(pos.longitude);
    final displayDate = DateFormat('dd-MM-yyyy').format(now);
    final dateDigits = DateFormat('ddMMyyyy').format(now);

    final code = generateCodeString(
      supervisorId: supervisorId,
      latitude: pos.latitude,
      longitude: pos.longitude,
      session: sessionWindow.session,
      date: now,
    );

    return SuperProctorData(
      code: code,
      supervisorId: supervisorId.trim().toUpperCase(),
      latitude: pos.latitude,
      longitude: pos.longitude,
      latDigit: latDigit,
      longDigit: longDigit,
      displayDate: displayDate,
      dateDigits: dateDigits,
      session: sessionWindow.session,
      centre: centre,
      examStart: sessionWindow.startTime,
      examEnd: sessionWindow.endTime,
      isExisting: false,
      createdAt: now,
    );
  }

  /// Saves the generated Super Proctor Code in the Bits-superproctor_code DynamoDB table via Lambda API
  Future<Map<String, dynamic>> submitSuperProctorCode(
    SuperProctorData data,
  ) async {
    try {
      final response = await ApiClient.sendAction(
        action: 'saveSuperProctorCode',
        payload: data.toJson(),
      );

      if (response['success'] == true) {
        return {
          'success': true,
          'message':
              response['message'] ?? 'Super Proctor Code saved successfully.',
          'code': data.code,
        };
      }

      return {
        'success': false,
        'error':
            response['error'] ??
            'Failed to save Super Proctor Code to database.',
      };
    } catch (e) {
      debugPrint(' [SuperProctorService] Error submitting code: $e');
      return {
        'success': false,
        'error': 'Network or server error while submitting code: $e',
      };
    }
  }
}
