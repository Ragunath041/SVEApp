/// Application Configuration
/// Centralized management for backend endpoints and operational timeouts.
class AppConfig {
  /// Consolidated backend Lambda Function URL (bits-supervisor_app-main)
  static String mainBackendUrl =
      'https://s4avs635aodhezapmgzcfwnje40yyqmx.lambda-url.us-east-1.on.aws/';

  /// Legacy Exam Lambda Function URL (consolidated into main backend)
  static const String legacyExamLambdaUrl =
      'https://s4avs635aodhezapmgzcfwnje40yyqmx.lambda-url.us-east-1.on.aws/';

  /// Default HTTP timeout duration
  static const Duration defaultTimeout = Duration(seconds: 25);

  /// S3 Upload timeout duration (longer for multi-page PDFs)
  static const Duration uploadTimeout = Duration(seconds: 60);

  /// Maximum upload retry attempts on network interruptions
  static const int maxUploadRetries = 2;

  /// Feature flag for AES-256-GCM client-side image encryption
  static bool enableImageEncryption = true;

  /// 256-bit (32-byte) AES secret key encoded in Base64
  static const String imageEncryptionKeyBase64 =
      'Yml0c3dpbHAtZXhhbS1hZXMyNTYtZmFjZS1rZXktMzI=';
}
