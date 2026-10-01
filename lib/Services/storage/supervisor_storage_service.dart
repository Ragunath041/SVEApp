import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/s3_uploader.dart';
import '../../core/security/image_encryption_service.dart';
import 's3_transfer_helper.dart';
import 'session_cache_service.dart';

/// Handles uploading and downloading supervisor profile data and face images
/// to/from S3 via secure pre-signed URLs.
class SupervisorStorageService {
  static const String _bucketName = 'bits-supervisorapp';

  /// Upload face image to S3 bucket
  static Future<Map<String, dynamic>> uploadFaceImage({
    required String imagePath,
    required String supervisorId,
    String suffix = 'face.jpg',
  }) async {
    try {
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        return {'success': false, 'error': 'Image file not found.'};
      }

      final imageBytes = await imageFile.readAsBytes();
      final payloadBytes =
          await ImageEncryptionService.encryptImageBytes(imageBytes);

      final result = await S3Uploader.requestUrlAndUpload(
        uploadType: 'supervisor_face',
        metadata: {
          'supervisorId': supervisorId,
          'suffix': suffix,
        },
        bytes: payloadBytes,
        contentType: 'image/jpeg',
      );

      if (result['success'] != true) {
        return {
          'success': false,
          'error': result['error'] ?? 'Failed to upload photo.',
        };
      }

      final fileName = result['key'] ?? 'Supervisor-details/$supervisorId/$suffix';
      final imageUrl = result['url'] ?? '';

      return {'success': true, 'url': imageUrl, 'key': fileName};
    } on SocketException {
      return {'success': false, 'error': 'No internet connection. Please check your network.'};
    } catch (e) {
      debugPrint(' [SupervisorStorage] Upload Error for $suffix: $e');
      return {
        'success': false,
        'error': 'Failed to upload photo: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}',
      };
    }
  }

  /// Download and decrypt supervisor face image from S3
  static Future<Uint8List?> downloadFaceImage({
    required String supervisorId,
    String suffix = 'face.jpg',
  }) async {
    try {
      final key = 'Supervisor-details/$supervisorId/$suffix';
      final rawBytes = await S3TransferHelper.download(
        bucket: _bucketName,
        key: key,
      );
      if (rawBytes == null) return null;
      return await ImageEncryptionService.decryptImageBytes(rawBytes);
    } catch (e) {
      debugPrint(' [SupervisorStorage] Failed to download/decrypt face image: $e');
      return null;
    }
  }

  /// Upload registration data as JSON to S3
  static Future<Map<String, dynamic>> uploadRegistrationData({
    required String supervisorId,
    required String fullName,
    required String email,
    required String centre,
    required String invigilatorType,
    required String phoneNumber,
    required String city,
    required String address,
    String? imageUrl,
    Map<String, String>? imageUrls,
  }) async {
    try {
      final registrationData = {
        'supervisor_id': supervisorId,
        'full_name': fullName,
        'email': email,
        'centre': centre,
        'invigilator_type': invigilatorType,
        'phone_number': phoneNumber,
        'city': city,
        'address': address,
        'face_image_url': imageUrl ?? '',
        'image_urls': imageUrls ?? {},
        'registered_at': DateTime.now().toIso8601String(),
      };

      final jsonData = jsonEncode(registrationData);

      final result = await S3Uploader.requestUrlAndUpload(
        uploadType: 'registration_json',
        metadata: {
          'supervisorId': supervisorId,
        },
        bytes: utf8.encode(jsonData),
        contentType: 'application/json',
      );

      if (result['success'] != true) {
        return {
          'success': false,
          'error': result['error'] ?? 'Failed to save registration.',
        };
      }

      final fileName = result['key'] ?? 'Supervisor-details/$supervisorId/registration.json';

      return {
        'success': true,
        'message': 'Registration data uploaded successfully.',
        'key': fileName,
      };
    } on SocketException {
      return {'success': false, 'error': 'No internet connection. Please check your network.'};
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to save registration: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}',
      };
    }
  }

  /// Complete registration: Upload images, upload JSON, and save locally
  static Future<Map<String, dynamic>> completeRegistration({
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
      String? imageUrl;
      Map<String, String> imageUrls = {};

      if (imagePaths != null && imagePaths.isNotEmpty) {
        for (var entry in imagePaths.entries) {
          final pose = entry.key;
          final path = entry.value;

          final imageUploadResult = await uploadFaceImage(
            imagePath: path,
            supervisorId: supervisorId,
            suffix: '$pose.jpg',
          );

          if (imageUploadResult['success']) {
            imageUrls[pose] = imageUploadResult['url'];
            if (pose == 'straight') {
              imageUrl = imageUploadResult['url'];
            }
          }
        }
      } else if (imagePath != null && imagePath.isNotEmpty) {
        final imageUploadResult = await uploadFaceImage(
          imagePath: imagePath,
          supervisorId: supervisorId,
        );

        if (imageUploadResult['success']) {
          imageUrl = imageUploadResult['url'];
          imageUrls['straight'] = imageUrl!;
        }
      }

      final dataUploadResult = await uploadRegistrationData(
        supervisorId: supervisorId,
        fullName: fullName,
        email: email,
        centre: centre,
        invigilatorType: invigilatorType,
        phoneNumber: phoneNumber,
        city: city,
        address: address,
        imageUrl: imageUrl,
        imageUrls: imageUrls,
      );

      if (!dataUploadResult['success']) {
        return dataUploadResult;
      }

      await SessionCacheService.saveToLocalStorage(
        supervisorId: supervisorId,
        fullName: fullName,
        email: email,
        centre: centre,
        invigilatorType: invigilatorType,
        phoneNumber: phoneNumber,
        city: city,
        address: address,
        imagePath: imagePath,
        imagePaths: imagePaths,
      );

      return {
        'success': true,
        'message': 'Registration completed successfully.',
        'image_url': imageUrl,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Registration failed: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}',
      };
    }
  }

  /// Download registration data from S3 and save to local storage
  static Future<Map<String, dynamic>> downloadRegistrationFromS3({
    required String supervisorId,
  }) async {
    try {
      final registrationKey =
          'Supervisor-details/$supervisorId/registration.json';

      final registrationBytes = await S3TransferHelper.download(
        bucket: _bucketName,
        key: registrationKey,
      );

      if (registrationBytes == null) {
        return {
          'success': false,
          'error': 'Registration not found. Please register first.',
        };
      }

      final registrationData = jsonDecode(utf8.decode(registrationBytes));

      // Download face embedding if available
      final embeddingKey =
          'Supervisor-details/$supervisorId/face_embedding.json';

      try {
        final embeddingBytes = await S3TransferHelper.download(
          bucket: _bucketName,
          key: embeddingKey,
        );

        if (embeddingBytes != null) {
          final embeddingData = jsonDecode(utf8.decode(embeddingBytes));
          final embedding = (embeddingData['embedding'] as List)
              .map((e) => (e as num).toDouble())
              .toList();

          final prefs = SharedPreferencesAsync();
          await prefs.setString(
            'face_embedding_$supervisorId',
            embedding.join(','),
          );
        }
      } catch (e) {
        debugPrint('SupervisorStorageService: Error caching embedding for $supervisorId: $e');
      }

      await SessionCacheService.saveToLocalStorage(
        supervisorId: supervisorId,
        fullName: registrationData['full_name'] ?? '',
        email: registrationData['email'] ?? '',
        centre: registrationData['centre'] ?? '',
        invigilatorType: registrationData['invigilator_type'] ?? '',
        phoneNumber: registrationData['phone_number'] ?? '',
        city: registrationData['city'] ?? '',
        address: registrationData['address'] ?? '',
        imagePath: null,
      );

      return {
        'success': true,
        'message': 'Registration data downloaded and synced successfully.',
        'data': registrationData,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to sync data: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}',
      };
    }
  }

  /// Update supervisor data in local storage and S3
  static Future<Map<String, dynamic>> updateSupervisorData({
    required String supervisorId,
    required String centre,
    required String invigilatorType,
  }) async {
    try {
      final existingData = await SessionCacheService.getLocalRegistrationData(supervisorId);

      if (existingData == null) {
        return {
          'success': false,
          'error': 'Data not found. Please register or login again.',
        };
      }

      existingData['centre'] = centre;
      existingData['invigilator_type'] = invigilatorType;
      existingData['updated_at'] = DateTime.now().toIso8601String();

      final prefs = SharedPreferencesAsync();
      await prefs.setString(
        'registration_$supervisorId',
        jsonEncode(existingData),
      );

      final registrationData = {
        'supervisor_id': supervisorId,
        'full_name': existingData['full_name'],
        'email': existingData['email'],
        'centre': centre,
        'invigilator_type': invigilatorType,
        'phone_number': existingData['phone_number'] ?? '',
        'city': existingData['city'] ?? '',
        'address': existingData['address'] ?? '',
        'face_image_url': existingData['face_image_url'] ?? '',
        'registered_at': existingData['registered_at'],
        'updated_at': existingData['updated_at'],
      };

      final jsonData = jsonEncode(registrationData);
      final fileName = 'Supervisor-details/$supervisorId/registration.json';

      final success = await S3TransferHelper.upload(
        bucket: _bucketName,
        key: fileName,
        body: utf8.encode(jsonData),
        contentType: 'application/json',
      );

      if (!success) {
        throw Exception('S3 upload returned false.');
      }

      return {
        'success': true,
        'message': 'Supervisor data updated successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to update information: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}',
      };
    }
  }
}
