import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages local device caching, supervisor session persistence,
/// and active exam timing window detection.
class SessionCacheService {
  /// Save registration data to local storage
  static Future<bool> saveToLocalStorage({
    required String supervisorId,
    required String fullName,
    required String email,
    required String centre,
    required String invigilatorType,
    required String phoneNumber,
    required String city,
    required String address,
    String? imagePath,
    Map<String, String>? imagePaths,
  }) async {
    try {
      final prefs = SharedPreferencesAsync();

      final registrationData = {
        'supervisor_id': supervisorId,
        'full_name': fullName,
        'email': email,
        'centre': centre,
        'invigilator_type': invigilatorType,
        'phone_number': phoneNumber,
        'city': city,
        'address': address,
        'image_path': imagePath ?? '',
        'images': imagePaths ?? {},
        'registered_at': DateTime.now().toIso8601String(),
      };

      final jsonString = jsonEncode(registrationData);
      await prefs.setString('registration_$supervisorId', jsonString);
      await prefs.setString('current_supervisor_id', supervisorId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get registration data from local storage
  static Future<Map<String, dynamic>?> getLocalRegistrationData(
    String supervisorId,
  ) async {
    try {
      final prefs = SharedPreferencesAsync();
      final jsonString = await prefs.getString('registration_$supervisorId');
      if (jsonString != null) {
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Helper to calculate current active exam session from cached timings
  static Future<Map<String, dynamic>?> getCurrentActiveExam(
    String centreName,
  ) async {
    Map<String, dynamic>? activeExam;
    try {
      final prefs = SharedPreferencesAsync();
      final now = DateTime.now();
      final todayDateStr = DateFormat('dd-MM-yyyy').format(now);

      final String? cachedJson = await prefs.getString('cached_center_timings');
      if (cachedJson == null) return null;

      final Map<String, dynamic> cachedData = jsonDecode(cachedJson);
      if (cachedData['date'] != todayDateStr) return null;

      final timings = Map<String, String>.from(cachedData['timings'] ?? {});

      for (String sessionType in ['FN', 'AN', 'EN']) {
        final String? startTimeStr = timings['${sessionType}_start'];
        final String? endTimeStr = timings['${sessionType}_end'];

        if (startTimeStr == null || startTimeStr.isEmpty) continue;

        final startParts = startTimeStr.split(':');
        final endParts = (endTimeStr ?? '23:59').split(':');

        final start = DateTime(
          now.year,
          now.month,
          now.day,
          int.parse(startParts[0]),
          int.parse(startParts[1]),
        );
        final end = DateTime(
          now.year,
          now.month,
          now.day,
          int.parse(endParts[0]),
          int.parse(endParts[1]),
        );
        final bufferStart = start.subtract(const Duration(minutes: 30));

        if (now.isAfter(bufferStart) && now.isBefore(end)) {
          activeExam = {
            'date': todayDateStr,
            'session': sessionType.trim(),
            'examStartTime': startTimeStr,
            'examEndTime': endTimeStr,
            'allowedStartTime': bufferStart.toIso8601String(),
            'parsedEndTime': end.toIso8601String(),
          };
          break;
        }
      }
      return activeExam;
    } catch (_) {
      return null;
    }
  }

  /// Mark a session as completed locally
  static Future<void> markSessionAsFinished(
    String supervisorId,
    String date,
    String session,
  ) async {
    final prefs = SharedPreferencesAsync();
    final key =
        'attendance_${supervisorId.trim()}_${date.trim()}_${session.trim()}';
    await prefs.setBool(key, true);
  }

  /// Check if a session is already marked as logged in
  static Future<bool> isSessionMarked(
    String supervisorId,
    String date,
    String session,
  ) async {
    final prefs = SharedPreferencesAsync();
    final key =
        'attendance_${supervisorId.trim()}_${date.trim()}_${session.trim()}';
    return await prefs.getBool(key) ?? false;
  }

  /// Explicitly save the current session window
  static Future<void> saveCurrentSessionWindow({
    required String startTime,
    required String endTime,
  }) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString('current_session_start', startTime);
    await prefs.setString('current_session_end', endTime);
  }

  /// Clear the explicit session window (on logout)
  static Future<void> clearCurrentSessionWindow() async {
    final prefs = SharedPreferencesAsync();
    await prefs.remove('current_session_start');
    await prefs.remove('current_session_end');
  }

  /// Clear all local registration data
  static Future<bool> clearAllRegistrationData() async {
    try {
      final prefs = SharedPreferencesAsync();
      final keys = await prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith('registration_') ||
            key.startsWith('face_embedding_')) {
          await prefs.remove(key);
        }
      }

      await prefs.remove('current_supervisor_id');
      return true;
    } catch (e) {
      return false;
    }
  }
}
