import 'supervisor_audit_log_service.dart';

/// Handles recording face detection events to the single unified S3 CSV log.
/// Routes events to S3://bitswilp-data/Supervisorapp_logs/logs.csv
class FaceTelemetryLogService {
  /// Log a face detection event (consolidated into primary supervisor actions)
  static Future<void> logFaceEvent({
    required String bitsId,
    required String action,
    required String status,
    String size = '',
    String angle = '',
    String center = '',
    String light = '',
    String deviceModel = 'Unknown',
  }) async {
    // Face telemetry is consolidated directly into the main LOGIN/REGISTRATION log entries
  }
}

/// Backward compatibility alias
typedef S3FaceLogService = FaceTelemetryLogService;
