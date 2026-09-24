import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Clean, robust HTTP Client for communicating with the bits-supervisor_app-main backend.
class ApiClient {
  static final http.Client _client = http.Client();

  /// Sends a structured action request to the consolidated Lambda backend.
  /// Automatically injects the `action` field and handles JSON encoding/decoding,
  /// timeouts, and network exceptions.
  static Future<Map<String, dynamic>> sendAction({
    required String action,
    Map<String, dynamic>? payload,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? AppConfig.defaultTimeout;
    final url = Uri.parse(AppConfig.mainBackendUrl);

    final requestBody = {
      'action': action,
      if (payload != null) ...payload,
    };

    try {
      debugPrint(' [ApiClient] Sending action "$action" to $url');

      final response = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(effectiveTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) {
          return {'success': true};
        }
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        return {'success': true, 'data': decoded};
      } else {
        debugPrint(
          ' [ApiClient] Server error ${response.statusCode}: ${response.body}',
        );
        String errorMsg = 'Server error (${response.statusCode})';
        try {
          final errJson = jsonDecode(response.body);
          if (errJson is Map && errJson.containsKey('error')) {
            errorMsg = errJson['error'].toString();
          }
        } catch (_) {}

        return {
          'success': false,
          'error': errorMsg,
          'statusCode': response.statusCode,
        };
      }
    } on SocketException catch (e) {
      debugPrint(' [ApiClient] No internet connection: $e');
      return {
        'success': false,
        'error': 'No internet connection. Please check your network and try again.',
        'errorType': 'network',
      };
    } on TimeoutException catch (e) {
      debugPrint(' [ApiClient] Request timed out: $e');
      return {
        'success': false,
        'error': 'Request timed out. Please check your connection.',
        'errorType': 'timeout',
      };
    } catch (e) {
      debugPrint(' [ApiClient] Unexpected error: $e');
      return {
        'success': false,
        'error': 'An unexpected error occurred: $e',
        'errorType': 'unknown',
      };
    }
  }

  /// Direct GET helper (for health checks or simple query parameter lookups)
  static Future<Map<String, dynamic>> get({
    Map<String, String>? queryParams,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? AppConfig.defaultTimeout;
    final uri = Uri.parse(AppConfig.mainBackendUrl).replace(
      queryParameters: queryParams,
    );

    try {
      debugPrint(' [ApiClient] GET $uri');
      final response = await _client.get(uri).timeout(effectiveTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {
        'success': false,
        'error': 'Server error (${response.statusCode})',
        'statusCode': response.statusCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
