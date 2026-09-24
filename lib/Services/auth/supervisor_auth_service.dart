import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';

/// Handles Supervisor authentication, registration validation, exam centre lookups,
/// and centre session timings via the backend API.
class SupervisorAuthService {
  SupervisorAuthService();

  /// Validates supervisor registration data
  Future<Map<String, dynamic>> validateSupervisor({
    required String supervisorId,
    required String centre,
    required String invigilatorType,
  }) async {
    try {
      final response = await ApiClient.sendAction(
        action: 'validateSupervisor',
        payload: {
          'supervisorId': supervisorId.trim(),
          'centre': centre.trim(),
          'invigilatorType': invigilatorType.trim(),
        },
      );

      return response;
    } on SocketException {
      return {
        'success': false,
        'error': 'Cannot connect. Please check internet availability.',
        'errorType': 'network',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Unable to connect. Please check your internet connection.',
        'errorType': 'connection',
      };
    }
  }

  /// Fetches supervisor details by ID from the backend API (bits-Supervisor-details)
  Future<Map<String, dynamic>> getSupervisorDetails(String supervisorId) async {
    try {
      var response = await ApiClient.sendAction(
        action: 'getSupervisorDetails',
        payload: {'supervisorId': supervisorId.trim()},
      );

      // Graceful fallback to validateSupervisor if Lambda has not yet refreshed
      if (response['success'] != true &&
          (response['error']?.toString().toLowerCase().contains(
                    'unsupported',
                  ) ==
                  true ||
              response['error']?.toString().toLowerCase().contains('unknown') ==
                  true)) {
        response = await ApiClient.sendAction(
          action: 'validateSupervisor',
          payload: {'supervisorId': supervisorId.trim()},
        );
      }

      if (response['success'] != true || response['data'] == null) {
        return {
          'success': false,
          'error': response['error'] ?? 'Supervisor not found in database.',
        };
      }

      final data = response['data'] as Map<String, dynamic>;
      final name =
          (data['name'] ?? data['full_name'] ?? data['Name'])
              ?.toString()
              .trim() ??
          '';
      final centre =
          (data['centre'] ?? data['Exam hall'] ?? data['center'])
              ?.toString()
              .trim() ??
          '';
      final type =
          (data['type'] ?? data['invigilator_type'] ?? data['Type'])
              ?.toString()
              .trim() ??
          '';
      final phone =
          (data['phone'] ?? data['phoneNumber'] ?? data['PhoneNumber'])
              ?.toString()
              .trim();
      final city = (data['city'] ?? data['City'])?.toString().trim() ?? '';
      final address =
          (data['address'] ?? data['Address'])?.toString().trim() ?? '';
      final email = (data['email'] ?? data['Email'])?.toString().trim() ?? '';

      return {
        'success': true,
        'data': {
          'name': name,
          'full_name': name,
          'Name': name,
          'centre': centre,
          'Exam hall': centre,
          'center': centre,
          'type': type,
          'Type': type,
          'invigilator_type': type,
          'phoneNumber': phone ?? '',
          'phone': phone ?? '',
          'city': city,
          'address': address,
          'email': email,
        },
      };
    } on SocketException {
      return {
        'success': false,
        'error': 'No Internet Connection.',
        'errorType': 'network',
      };
    } catch (e) {
      debugPrint('getSupervisorDetails error: $e');
      return {
        'success': false,
        'error': 'Failed to fetch data. Please try again.',
      };
    }
  }

  /// Update supervisor details
  Future<Map<String, dynamic>> updateSupervisor({
    required String supervisorId,
    required String centre,
    required String invigilatorType,
    String? phoneNumber,
    String? city,
    String? address,
    String? name,
    String? email,
  }) async {
    try {
      final response = await ApiClient.sendAction(
        action: 'updateSupervisor',
        payload: {
          'supervisorId': supervisorId.trim(),
          'centre': centre.trim(),
          'invigilatorType': invigilatorType.trim(),
          if (phoneNumber != null) 'phoneNumber': phoneNumber.trim(),
          if (city != null) 'city': city.trim(),
          if (address != null) 'address': address.trim(),
          if (name != null) 'name': name.trim(),
          if (email != null) 'email': email.trim(),
        },
      );

      if (response['success'] == true) {
        return {
          'success': true,
          'message': 'Supervisor details updated successfully in DynamoDB.',
        };
      }

      return {
        'success': false,
        'error': response['error'] ?? 'Failed to update information.',
      };
    } on SocketException {
      return {
        'success': false,
        'error': 'No Internet Connection.',
        'errorType': 'network',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to update information. Please try again.',
      };
    }
  }

  /// Check if supervisor is already registered
  Future<Map<String, dynamic>> checkIfAlreadyRegistered({
    required String supervisorId,
    required String email,
  }) async {
    try {
      final response = await ApiClient.sendAction(
        action: 'validateSupervisor',
        payload: {'supervisorId': supervisorId.trim()},
      );

      if (response['success'] != true || response['data'] == null) {
        return {
          'success': true,
          'isRegistered': false,
          'message': 'Supervisor not found in database.',
        };
      }

      final data = response['data'] as Map<String, dynamic>;
      final dbEmail = (data['email'] ?? '').toString().trim();

      if (dbEmail.isNotEmpty &&
          dbEmail.toLowerCase() != email.trim().toLowerCase()) {
        return {
          'success': false,
          'isRegistered': false,
          'error': 'Email does not match our records.',
          'expectedEmail': dbEmail,
        };
      }

      return {
        'success': true,
        'isRegistered': false,
        'message': 'Supervisor can proceed with registration.',
      };
    } on SocketException {
      return {
        'success': false,
        'error': 'No Internet Connection.',
        'errorType': 'network',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to verify registration. Please try again.',
      };
    }
  }

  /// Fetches session timings for a specific centre
  Future<Map<String, dynamic>> getCenterTimings(String centreName) async {
    try {
      final response = await ApiClient.sendAction(
        action: 'getCenterTimings',
        payload: {'centre': centreName.trim()},
      );

      if (response['success'] == true && response['timings'] != null) {
        final rawTimings = response['timings'] as Map<String, dynamic>;
        final Map<String, String> mappedTimings = {
          'FN_start': rawTimings['FN_start']?.toString() ?? '',
          'FN_end': rawTimings['FN_end']?.toString() ?? '',
          'AN_start': rawTimings['AN_start']?.toString() ?? '',
          'AN_end': rawTimings['AN_end']?.toString() ?? '',
          'EN_start': rawTimings['EN_start']?.toString() ?? '',
          'EN_end': rawTimings['EN_end']?.toString() ?? '',
        };
        return {'success': true, 'data': mappedTimings};
      }

      return {
        'success': false,
        'error': response['error'] ?? 'No timings found for $centreName',
      };
    } on SocketException {
      return {'success': false, 'error': 'No Internet Connection.'};
    } catch (e) {
      debugPrint(' [SupervisorAuthService] Error fetching center timings: $e');
      return {'success': false, 'error': 'Failed to fetch exam timings.'};
    }
  }

  /// Scans and returns all centre names sorted A-Z
  Future<Map<String, dynamic>> getAllExamCentres() async {
    try {
      final response = await ApiClient.sendAction(action: 'getCentres');

      if (response['success'] == true && response['centres'] != null) {
        final rawCentres = response['centres'] as List;
        final List<String> centres = [];

        for (final item in rawCentres) {
          if (item is Map && item['name'] != null) {
            final name = item['name'].toString().trim();
            if (name.isNotEmpty) centres.add(name);
          } else if (item is String && item.trim().isNotEmpty) {
            centres.add(item.trim());
          }
        }

        centres.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return {'success': true, 'centres': centres};
      }

      return {
        'success': false,
        'error': response['error'] ?? 'Failed to fetch exam centres.',
      };
    } on SocketException {
      return {
        'success': false,
        'error': 'No Internet Connection.',
        'errorType': 'network',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to fetch exam centres. Please try again.',
      };
    }
  }

  void dispose() {}
}

/// Backward compatibility alias
typedef DynamoDBService = SupervisorAuthService;
