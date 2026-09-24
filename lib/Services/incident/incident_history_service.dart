import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';

/// Fetches submitted malpractice and incident history for a supervisor.
class IncidentHistoryService {
  IncidentHistoryService();

  /// Fetches all incidents for a specific supervisor, grouped by date.
  /// Returns a Map where key is Date (YYYY-MM-DD) and value is List of Incident Maps.
  Future<Map<String, List<Map<String, dynamic>>>> fetchIncidentHistory(
    String supervisorId,
  ) async {
    Map<String, List<Map<String, dynamic>>> history = {};

    try {
      debugPrint(' [IncidentHistoryService] Fetching history for $supervisorId');

      final response = await ApiClient.sendAction(
        action: 'getIncidentHistory',
        payload: {
          'supervisorId': supervisorId.trim(),
        },
      );

      if (response['success'] == true && response['history'] != null) {
        final rawHistory = response['history'] as Map<String, dynamic>;

        rawHistory.forEach((dateKey, incidentList) {
          if (incidentList is List) {
            history[dateKey] = incidentList
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
          }
        });
      }

      return history;
    } catch (e) {
      debugPrint(' [IncidentHistoryService] Fetch error: $e');
      return history;
    }
  }

  void dispose() {}
}

/// Backward compatibility alias
typedef S3IncidentService = IncidentHistoryService;
