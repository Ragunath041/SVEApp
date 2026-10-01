import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import 'api_client.dart';

/// Pure HTTP S3 Uploader using AWS Pre-signed URLs.
/// Requires ZERO client-side AWS IAM credentials, eliminating clock skew and SigV4 hashing.
class S3Uploader {
  static final HttpClient _ioClient = HttpClient()..autoUncompress = false;

  /// Uploads binary bytes directly to an S3 Pre-signed URL using HTTP PUT.
  /// Explicitly sets Content-Length to prevent 'Transfer-Encoding: chunked'
  /// which AWS S3 rejects with HTTP 501 (NotImplemented).
  static Future<bool> uploadBytes({
    required String presignedUrl,
    required List<int> bytes,
    required String contentType,
    Map<String, String>? headers,
    int maxRetries = AppConfig.maxUploadRetries,
  }) async {
    if (bytes.isEmpty) {
      debugPrint(
        '🚨 [S3Uploader] Refusing to upload empty 0-byte buffer to S3!',
      );
      return false;
    }

    final uri = Uri.parse(presignedUrl);

    int attempts = 0;
    while (attempts <= maxRetries) {
      attempts++;
      try {
        debugPrint(
          ' [S3Uploader] Uploading ${bytes.length} bytes (Attempt $attempts/${maxRetries + 1})...',
        );

        final request = await _ioClient.putUrl(uri);
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
        request.contentLength =
            bytes.length; // CRITICAL for AWS S3 presigned PUT

        if (headers != null) {
          headers.forEach((key, value) {
            request.headers.set(key, value);
          });
        }

        request.add(bytes);
        final response = await request.close().timeout(AppConfig.uploadTimeout);
        final responseBody = await utf8.decodeStream(response);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          debugPrint(
            ' [S3Uploader] Upload succeeded (HTTP ${response.statusCode}, ${bytes.length} bytes)',
          );
          return true;
        } else {
          debugPrint(
            ' [S3Uploader] S3 returned HTTP ${response.statusCode}: $responseBody',
          );
          if (responseBody.contains('<Error>') ||
              responseBody.contains('"message"')) {
            debugPrint('⚠️ [S3Uploader] S3 Error details: $responseBody');
          }
          if (attempts > maxRetries) {
            return false;
          }
        }
      } on SocketException catch (e) {
        debugPrint(' [S3Uploader] Network error on attempt $attempts: $e');
        if (attempts > maxRetries) return false;
      } on TimeoutException catch (e) {
        debugPrint(' [S3Uploader] Upload timed out on attempt $attempts: $e');
        if (attempts > maxRetries) return false;
      } catch (e) {
        debugPrint(
          ' [S3Uploader] Unexpected upload error on attempt $attempts: $e',
        );
        if (attempts > maxRetries) return false;
      }

      // Exponential backoff wait before retrying (1s, 2s...)
      await Future.delayed(Duration(seconds: attempts));
    }

    return false;
  }

  /// High-level workflow: Requests a pre-signed URL from Lambda and uploads the bytes.
  static Future<Map<String, dynamic>> requestUrlAndUpload({
    required String uploadType,
    required Map<String, dynamic> metadata,
    required List<int> bytes,
    required String contentType,
    Map<String, String>? headers,
  }) async {
    try {
      // 1. Request pre-signed URL from our Lambda backend
      final presignResult = await ApiClient.sendAction(
        action: 'getPresignedUploadUrl',
        payload: {
          'uploadType': uploadType,
          'metadata': metadata,
          'contentType': contentType,
        },
      );

      if (presignResult['success'] != true ||
          presignResult['uploadUrl'] == null) {
        return {
          'success': false,
          'error':
              presignResult['error'] ?? 'Failed to get upload authorization.',
        };
      }

      final String uploadUrl = presignResult['uploadUrl'];
      final String fileKey = presignResult['key'] ?? '';
      final String bucket = presignResult['bucket'] ?? '';

      // Prepare headers required by S3 (including any signed metadata headers)
      final Map<String, String> uploadHeaders = {};
      if (metadata.containsKey('s3Metadata') && metadata['s3Metadata'] is Map) {
        final s3Meta = metadata['s3Metadata'] as Map;
        s3Meta.forEach((key, value) {
          uploadHeaders['x-amz-meta-${key.toString().toLowerCase()}'] = value
              .toString();
        });
      }
      if (metadata.containsKey('pageCount') &&
          !uploadHeaders.containsKey('x-amz-meta-pages')) {
        uploadHeaders['x-amz-meta-pages'] = metadata['pageCount'].toString();
      }
      if (metadata.containsKey('pages') &&
          !uploadHeaders.containsKey('x-amz-meta-pages')) {
        uploadHeaders['x-amz-meta-pages'] = metadata['pages'].toString();
      }
      if (headers != null) {
        uploadHeaders.addAll(headers);
      }

      // 2. Upload bytes directly to S3 via HTTP PUT
      final bool uploadSuccess = await uploadBytes(
        presignedUrl: uploadUrl,
        bytes: bytes,
        contentType: contentType,
        headers: uploadHeaders.isNotEmpty ? uploadHeaders : null,
      );

      if (!uploadSuccess) {
        return {
          'success': false,
          'error':
              'S3 upload failed. Please check your internet connection and try again.',
        };
      }

      return {
        'success': true,
        'key': fileKey,
        'bucket': bucket,
        'url': uploadUrl
            .split('?')
            .first, // Clean S3 object URL without query params
      };
    } catch (e) {
      debugPrint(' [S3Uploader] High-level upload failed: $e');
      return {'success': false, 'error': 'Upload error: $e'};
    }
  }
}
