import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/network/api_client.dart';

/// Handles supervisor GPS location acquisition, exam centre geolocation fence validation,
/// and check-in / check-out attendance recording.
class SupervisorAttendanceService {
  SupervisorAttendanceService();

  /// Get current GPS location
  Future<Map<String, dynamic>> getCurrentLocation() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return {
          'success': false,
          'error': 'Location services are disabled. Please enable GPS.',
        };
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return {'success': false, 'error': 'Location permission denied.'};
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return {
          'success': false,
          'error':
              'Location permissions are permanently denied. Please enable them in settings.',
        };
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (e) {
        debugPrint(
          '[AttendanceService] High-accuracy GPS timed out or failed ($e), trying last known position...',
        );
        position = await Geolocator.getLastKnownPosition();
        if (position == null) {
          try {
            position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 5),
              ),
            );
          } catch (e) {
            debugPrint('[AttendanceService] Medium-accuracy GPS fallback also failed: $e');
          }
        }
      }

      if (position == null) {
        return {
          'success': false,
          'error':
              'Unable to get GPS location. Please check your device location settings.',
        };
      }

      return {
        'success': true,
        'latitude': position.latitude,
        'longitude': position.longitude,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Unable to get your location. Please check GPS settings.',
      };
    }
  }

  /// Validate if current location is within centre boundaries
  Future<Map<String, dynamic>> validateLocationForCentre({
    required String centreName,
    required double currentLatitude,
    required double currentLongitude,
  }) async {
    try {
      final response = await ApiClient.sendAction(action: 'getCentres');

      if (response['success'] != true || response['centres'] == null) {
        return {
          'success': false,
          'error': 'Unable to retrieve centre details for validation.',
        };
      }

      final List rawCentres = response['centres'] as List;
      Map<String, dynamic>? matchedCentre;

      for (var item in rawCentres) {
        if (item is Map) {
          final name = (item['name'] ?? item['centre'] ?? '').toString().trim();
          if (name.toLowerCase() == centreName.trim().toLowerCase()) {
            matchedCentre = Map<String, dynamic>.from(item);
            break;
          }
        }
      }

      if (matchedCentre == null) {
        return {
          'success': false,
          'error': 'Centre $centreName not found in database.',
        };
      }

      debugPrint('RAW CENTRE ITEM: $matchedCentre');

      final lat1 =
          double.tryParse(matchedCentre['maxLatitude']?.toString() ?? '0') ??
          0.0;
      final lat2 =
          double.tryParse(matchedCentre['minLatitude']?.toString() ?? '0') ??
          0.0;
      final long1 =
          double.tryParse(matchedCentre['maxLongitude']?.toString() ?? '0') ??
          0.0;
      final long2 =
          double.tryParse(matchedCentre['minLongitude']?.toString() ?? '0') ??
          0.0;

      final minLat = lat1 < lat2 ? lat1 : lat2;
      final maxLat = lat1 > lat2 ? lat1 : lat2;
      final minLong = long1 < long2 ? long1 : long2;
      final maxLong = long1 > long2 ? long1 : long2;

      // 0.005 degree buffer (~500 meters) to account for GPS inaccuracy
      const double buffer = 0.005;

      bool isWithinBounds =
          currentLatitude >= (minLat - buffer) &&
          currentLatitude <= (maxLat + buffer) &&
          currentLongitude >= (minLong - buffer) &&
          currentLongitude <= (maxLong + buffer);

      if (!isWithinBounds) {
        debugPrint('Location Check failed for $centreName:');
        debugPrint('Current: $currentLatitude, $currentLongitude');
        debugPrint('Bounds: $minLat-$maxLat, $minLong-$maxLong');

        return {
          'success': false,
          'error':
              'You are outside the designated boundaries of $centreName. Please verify your location at the exam centre.',
          'details': {
            'current_lat': currentLatitude,
            'current_long': currentLongitude,
            'centre_bounds': {
              'min_lat': minLat,
              'max_lat': maxLat,
              'min_long': minLong,
              'max_long': maxLong,
            },
          },
        };
      }

      return {
        'success': true,
        'message': 'Location validated successfully',
        'latitude': currentLatitude,
        'longitude': currentLongitude,
      };
    } catch (e) {
      debugPrint('❌ Location Validation Error: $e');
      return {
        'success': false,
        'error': 'Unable to validate location. Please try again.',
      };
    }
  }

  /// Mark supervisor attendance in DynamoDB via backend
  Future<Map<String, dynamic>> markAttendance({
    required String supervisorId,
    required String centre,
    required String name,
    required String email,
    required String invigilatorType,
    required double latitude,
    required double longitude,
    required String type, // "login" or "logout"
  }) async {
    try {
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final time =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      final response = await ApiClient.sendAction(
        action: 'supervisorCheckIn',
        payload: {
          'supervisorId': supervisorId.trim(),
          'centre': centre.trim(),
          'name': name.trim(),
          'email': email.trim(),
          'invigilatorType': invigilatorType.trim(),
          'latitude': latitude,
          'longitude': longitude,
          'type': type,
          'date': date,
          'time': time,
          'timestamp': now.toIso8601String(),
        },
      );

      if (response['success'] == true) {
        return {
          'success': true,
          'message': 'Attendance marked successfully.',
          'data': {
            'supervisor_id': supervisorId,
            'name': name,
            'email': email,
            'invigilator_type': invigilatorType,
            'centre': centre,
            'date': date,
            'time': time,
            'latitude': latitude,
            'longitude': longitude,
          },
        };
      }

      return {
        'success': false,
        'error': response['error'] ?? 'Failed to mark attendance.',
      };
    } on SocketException {
      return {
        'success': false,
        'error': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to mark attendance. Please try again.',
      };
    }
  }

  void dispose() {}
}

/// Backward compatibility alias
typedef AttendanceService = SupervisorAttendanceService;
