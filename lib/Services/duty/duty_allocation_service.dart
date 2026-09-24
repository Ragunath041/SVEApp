import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../models/supervisor_requirement_slot.dart';

/// Handles supervisor duty requirements discovery and expression of interest requests.
class DutyAllocationService {
  DutyAllocationService();

  /// Fetches duty requirements from backend API.
  Future<Map<String, dynamic>> fetchRequirements({String? supervisorId}) async {
    try {
      final response = await ApiClient.sendAction(
        action: 'getRequirements',
        payload: {
          if (supervisorId != null && supervisorId.isNotEmpty)
            'supervisorId': supervisorId.trim(),
        },
      );

      if (response['success'] != true || response['slots'] == null) {
        return {
          'success': false,
          'error': response['error'] ?? 'Failed to load supervisor requirements.',
          'errorType': 'backend',
        };
      }

      final List rawSlots = response['slots'] as List;
      final List<SupervisorRequirementSlot> slots = [];

      for (var item in rawSlots) {
        if (item is Map) {
          slots.add(
            SupervisorRequirementSlot(
              reqId: (item['reqId'] ?? '').toString(),
              city: (item['city'] ?? '').toString(),
              center: (item['center'] ?? '').toString(),
              date: (item['date'] ?? '').toString(),
              session: (item['session'] ?? '').toString(),
              requiredCount: (item['requiredCount'] as num?)?.toInt() ?? 0,
              currentRequestCount: (item['currentRequestCount'] as num?)?.toInt() ?? 0,
              isSubmitted: item['isSubmitted'] == true,
              isFull: item['isFull'] == true,
            ),
          );
        }
      }

      return {'success': true, 'slots': slots};
    } on SocketException catch (e) {
      debugPrint('SocketException fetching requirements: $e');
      return {
        'success': false,
        'error': 'No internet connection. Please check your network.',
        'errorType': 'network',
      };
    } catch (e) {
      debugPrint('Error fetching requirements: $e');
      return {
        'success': false,
        'error': 'Failed to load supervisor requirements: ${e.toString()}',
        'errorType': 'unknown',
      };
    }
  }

  /// Submits supervisor interest requests
  Future<Map<String, dynamic>> submitInterestRequests({
    required String supervisorId,
    required List<SupervisorRequirementSlot> selectedSlots,
  }) async {
    try {
      final formattedSlots = selectedSlots.map((slot) => {
        'reqId': slot.reqId,
        'session': slot.session,
      }).toList();

      final response = await ApiClient.sendAction(
        action: 'expressInterest',
        payload: {
          'supervisorId': supervisorId.trim(),
          'slots': formattedSlots,
        },
      );

      if (response['success'] == true) {
        return {'success': true};
      }

      return {
        'success': false,
        'error': response['error'] ?? 'Failed to submit interest request.',
      };
    } on SocketException catch (e) {
      debugPrint('SocketException submitting requests: $e');
      return {
        'success': false,
        'error': 'No internet connection. Please check your network.',
        'errorType': 'network',
      };
    } catch (e) {
      debugPrint('Error submitting requests: $e');
      return {
        'success': false,
        'error': 'Failed to submit interest request: ${e.toString()}',
        'errorType': 'unknown',
      };
    }
  }

  void dispose() {}
}

/// Backward compatibility alias
typedef SupervisorRequirementService = DutyAllocationService;
