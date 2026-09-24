import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/network/api_client.dart';
import '../../core/network/s3_uploader.dart';
import '../../core/security/image_encryption_service.dart';

/// Clean S3 Transfer helper using Pre-signed URLs via backend Lambda.
/// Provides pure binary upload and download with zero client-side AWS secrets.
class S3TransferHelper {
  /// Upload binary data to S3 using a pre-signed PUT URL.
  static Future<bool> upload({
    required String bucket,
    required String key,
    required List<int> body,
    required String contentType,
    Map<String, String>? metadata,
  }) async {
    try {
      debugPrint(
        ' [S3TransferHelper] Requesting presigned upload URL for $bucket/$key',
      );

      final presignResult = await ApiClient.sendAction(
        action: 'getPresignedUploadUrl',
        payload: {
          'uploadType': 'custom',
          'bucket': bucket,
          'key': key,
          'contentType': contentType,
          'metadata': metadata ?? {},
        },
      );

      if (presignResult['success'] != true ||
          presignResult['uploadUrl'] == null) {
        debugPrint(
          ' [S3TransferHelper.upload] Failed to get presigned URL: ${presignResult['error']}',
        );
        return false;
      }

      final String uploadUrl = presignResult['uploadUrl'];

      final Map<String, String> uploadHeaders = {};
      if (metadata != null && metadata.isNotEmpty) {
        metadata.forEach((key, value) {
          uploadHeaders['x-amz-meta-${key.toString().toLowerCase()}'] = value
              .toString();
        });
      }

      final success = await S3Uploader.uploadBytes(
        presignedUrl: uploadUrl,
        bytes: body,
        contentType: contentType,
        headers: uploadHeaders.isNotEmpty ? uploadHeaders : null,
      );

      if (success) {
        debugPrint(' [S3TransferHelper.upload] Successfully uploaded to $key');
      } else {
        debugPrint(' [S3TransferHelper.upload] Upload failed for $key');
      }

      return success;
    } catch (e) {
      debugPrint(' [S3TransferHelper.upload] Error: $e');
      return false;
    }
  }

  /// Download binary data from S3 using a pre-signed GET URL.
  static Future<Uint8List?> download({
    required String bucket,
    required String key,
  }) async {
    try {
      debugPrint(
        ' [S3TransferHelper] Requesting presigned download URL for $bucket/$key',
      );

      final presignResult = await ApiClient.sendAction(
        action: 'getPresignedDownloadUrl',
        payload: {'bucket': bucket, 'key': key},
      );

      if (presignResult['success'] != true ||
          presignResult['downloadUrl'] == null) {
        debugPrint(
          ' [S3TransferHelper.download] Failed to get presigned URL: ${presignResult['error']}',
        );
        return null;
      }

      final String downloadUrl = presignResult['downloadUrl'];

      final response = await http.get(Uri.parse(downloadUrl));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint(
          ' [S3TransferHelper.download] Successfully downloaded $key (${response.bodyBytes.length} bytes)',
        );
        return response.bodyBytes;
      } else if (response.statusCode == 404) {
        debugPrint(' [S3TransferHelper.download] Object not found (404): $key');
        return null;
      } else {
        debugPrint(
          ' [S3TransferHelper.download] S3 returned HTTP ${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      debugPrint(' [S3TransferHelper.download] Error: $e');
      return null;
    }
  }

  /// Download image bytes from S3 and decrypt them via [ImageEncryptionService].
  static Future<Uint8List?> downloadImage({
    required String bucket,
    required String key,
  }) async {
    final rawBytes = await download(bucket: bucket, key: key);
    if (rawBytes == null) return null;
    return await ImageEncryptionService.decryptImageBytes(rawBytes);
  }
}

/// Backward compatibility alias
typedef S3Helper = S3TransferHelper;
