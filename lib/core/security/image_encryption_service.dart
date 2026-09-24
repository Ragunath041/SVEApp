import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

/// Authentication exception thrown when image decryption fails
/// due to MAC tag mismatch or corrupted/tampered ciphertext.
/// Implements both [Exception] and [Error] for compatibility with any caller error handling.
class ImageAuthenticationException extends Error implements Exception {
  final String message;
  final dynamic cause;

  ImageAuthenticationException(this.message, [this.cause]);

  @override
  String toString() =>
      'ImageAuthenticationException: $message${cause != null ? " (cause: $cause)" : ""}';
}

/// Service providing AES-256-GCM encryption and decryption for image bytes.
///
/// Output Payload Format:
/// `[ 12-byte Nonce ] + [ Ciphertext (N bytes) ] + [ 16-byte MAC Authentication Tag ]`
/// Total binary overhead: 28 bytes.
class ImageEncryptionService {
  /// Length of the AES-GCM initialization vector / nonce (12 bytes)
  static const int nonceLength = 12;

  /// Length of the Galois/Counter Mode authentication tag (16 bytes)
  static const int macLength = 16;

  /// Minimum binary overhead for valid encrypted payload (12 + 16 = 28 bytes)
  static const int overheadLength = nonceLength + macLength;

  /// Standard JPEG SOI (Start Of Image) magic bytes
  static const List<int> jpegMagicBytes = [0xFF, 0xD8];

  /// AES-256-GCM algorithm instance from package:cryptography
  static final AesGcm _algorithm = AesGcm.with256bits();

  /// Cached SecretKey instance to avoid decoding base64 on every operation
  static SecretKey? _cachedSecretKey;
  static String? _cachedKeyBase64;

  /// Retrieves or constructs the [SecretKey] from [AppConfig.imageEncryptionKeyBase64]
  static SecretKey getSecretKey([String? customKeyBase64]) {
    final keyBase64 = customKeyBase64 ?? AppConfig.imageEncryptionKeyBase64;
    if (_cachedSecretKey != null && _cachedKeyBase64 == keyBase64) {
      return _cachedSecretKey!;
    }
    final keyBytes = base64.decode(keyBase64);
    if (keyBytes.length != 32) {
      throw ArgumentError(
        'Image encryption key must be exactly 256 bits (32 bytes). Found ${keyBytes.length} bytes.',
      );
    }
    _cachedKeyBase64 = keyBase64;
    _cachedSecretKey = SecretKey(keyBytes);
    return _cachedSecretKey!;
  }

  /// Clears the cached SecretKey (useful for testing)
  @visibleForTesting
  static void resetKeyCache() {
    _cachedSecretKey = null;
    _cachedKeyBase64 = null;
  }

  /// Checks whether [bytes] starts with the JPEG SOI magic header `0xFF, 0xD8`.
  static bool isPlainJpeg(Uint8List bytes) {
    if (bytes.length < 2) return false;
    return bytes[0] == 0xFF && bytes[1] == 0xD8;
  }

  /// Encrypts raw image bytes using AES-256-GCM.
  ///
  /// Returns the concatenated binary stream:
  /// `[ 12-byte Nonce ] + [ Ciphertext ] + [ 16-byte MAC Tag ]`
  ///
  /// If [AppConfig.enableImageEncryption] is disabled or [plainBytes] is empty,
  /// returns [plainBytes] as-is.
  static Future<Uint8List> encryptImageBytes(
    Uint8List plainBytes, {
    SecretKey? secretKey,
  }) async {
    if (!AppConfig.enableImageEncryption || plainBytes.isEmpty) {
      return plainBytes;
    }

    final effectiveKey = secretKey ?? getSecretKey();

    // Generate a fresh, cryptographically secure 12-byte Nonce per encryption.
    // Safeguard: Ensure the generated Nonce does NOT accidentally start with
    // the JPEG magic header [0xFF, 0xD8], guaranteeing zero collision with plain JPEGs.
    List<int> nonce = _algorithm.newNonce();
    while (nonce.length >= 2 && nonce[0] == 0xFF && nonce[1] == 0xD8) {
      nonce = _algorithm.newNonce();
    }

    final secretBox = await _algorithm.encrypt(
      plainBytes,
      secretKey: effectiveKey,
      nonce: nonce,
    );

    // Concatenate into a single contiguous binary stream:
    // [ 12-byte Nonce ] + [ Ciphertext (N bytes) ] + [ 16-byte MAC Tag ]
    final concatenated = secretBox.concatenation(
      nonce: true,
      mac: true,
    );

    return Uint8List.fromList(concatenated);
  }

  /// Decrypts AES-256-GCM encrypted image bytes.
  ///
  /// Unpacks `[ 12-byte Nonce ] + [ Ciphertext ] + [ 16-byte MAC Tag ]` and decrypts.
  ///
  /// Backward Compatibility:
  /// - If [plainBytes] starts with JPEG magic header `0xFF, 0xD8`, returns as-is.
  /// - If [encryptedBytes.length < 28], returns as-is.
  /// - If [AppConfig.enableImageEncryption] is disabled, returns as-is.
  ///
  /// Throws [ImageAuthenticationException] (and [SecretBoxAuthenticationError] cause)
  /// if the MAC tag does not match or data is corrupted/tampered with.
  static Future<Uint8List> decryptImageBytes(
    Uint8List encryptedBytes, {
    SecretKey? secretKey,
  }) async {
    if (!AppConfig.enableImageEncryption || encryptedBytes.isEmpty) {
      return encryptedBytes;
    }

    // Backward compatibility: If it already begins with the JPEG magic header,
    // it is a legacy unencrypted JPEG—return it as-is without decrypting.
    if (isPlainJpeg(encryptedBytes)) {
      return encryptedBytes;
    }

    // Minimum size check: Must have at least 12-byte Nonce + 16-byte MAC (28 bytes)
    if (encryptedBytes.length < overheadLength) {
      return encryptedBytes;
    }

    final effectiveKey = secretKey ?? getSecretKey();

    // Unpack Nonce (12 bytes), Ciphertext (N bytes), and MAC (16 bytes)
    final secretBox = SecretBox.fromConcatenation(
      encryptedBytes,
      nonceLength: nonceLength,
      macLength: macLength,
    );

    try {
      final clearBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: effectiveKey,
      );

      return Uint8List.fromList(clearBytes);
    } on SecretBoxAuthenticationError catch (e) {
      debugPrint(
        '🚨 [ImageEncryptionService.decryptImageBytes] Authentication failed: MAC tag mismatch or tampered ciphertext.',
      );
      throw ImageAuthenticationException(
        'Decryption authentication failed: image payload has been tampered with or corrupted.',
        e,
      );
    } catch (e) {
      if (e is ImageAuthenticationException) rethrow;
      debugPrint(
        '🚨 [ImageEncryptionService.decryptImageBytes] Decryption error: $e',
      );
      throw ImageAuthenticationException(
        'Failed to decrypt image payload: $e',
        e,
      );
    }
  }
}
