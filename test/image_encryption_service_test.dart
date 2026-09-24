import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:supervisorapp/core/config/app_config.dart';
import 'package:supervisorapp/core/security/image_encryption_service.dart';

void main() {
  // Sample synthetic JPEG byte stream
  // Standard JPEG starts with 0xFF, 0xD8 and ends with 0xFF, 0xD9
  final Uint8List sampleJpeg = Uint8List.fromList([
    0xFF, 0xD8, // JPEG SOI (Start of Image)
    0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01,
    0x00, 0x60, 0x00, 0x60, 0x00, 0x00, // APP0 JFIF marker
    0xFF, 0xDB, 0x00, 0x43, 0x00, // DQT marker
    ...List.generate(64, (i) => (i * 7) % 256), // Quantization table data
    0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00,
    0x3F, 0x00, // SOS marker
    ...List.generate(128, (i) => (i * 13) % 256), // Sample compressed scan data
    0xFF, 0xD9, // JPEG EOI (End of Image)
  ]);

  setUp(() {
    AppConfig.enableImageEncryption = true;
    ImageEncryptionService.resetKeyCache();
  });

  group('ImageEncryptionService - Core AES-256-GCM', () {
    test(
      '1. Complete encryption -> decryption cycle verifies output matches original bytes and retains valid JPEG format',
      () async {
        final originalLength = sampleJpeg.length;
        expect(ImageEncryptionService.isPlainJpeg(sampleJpeg), isTrue);

        // Encrypt
        final encryptedBytes = await ImageEncryptionService.encryptImageBytes(
          sampleJpeg,
        );

        // Payload must be packed as: [ 12-byte Nonce ] + [ Ciphertext (N bytes) ] + [ 16-byte MAC ]
        expect(encryptedBytes.length, equals(originalLength + 28));

        // The encrypted payload MUST NOT begin with plain JPEG header 0xFF, 0xD8
        expect(ImageEncryptionService.isPlainJpeg(encryptedBytes), isFalse);
        expect(encryptedBytes, isNot(equals(sampleJpeg)));

        // Decrypt
        final decryptedBytes = await ImageEncryptionService.decryptImageBytes(
          encryptedBytes,
        );

        // Verify decrypted output is byte-for-byte identical to original
        expect(decryptedBytes, equals(sampleJpeg));

        // Verifies output retains valid JPEG magic format
        expect(ImageEncryptionService.isPlainJpeg(decryptedBytes), isTrue);
        expect(decryptedBytes.first, equals(0xFF));
        expect(decryptedBytes[1], equals(0xD8));
        expect(decryptedBytes[decryptedBytes.length - 2], equals(0xFF));
        expect(decryptedBytes.last, equals(0xD9));
      },
    );

    test(
      '2. Backward compatibility: passing an unencrypted JPEG returns identical bytes unmodified without decrypting',
      () async {
        expect(ImageEncryptionService.isPlainJpeg(sampleJpeg), isTrue);

        final result = await ImageEncryptionService.decryptImageBytes(
          sampleJpeg,
        );

        // Must return identical bytes unmodified without throwing an error
        expect(result, equals(sampleJpeg));
      },
    );

    test(
      '3. Tamper detection: modifying even a single byte of the encrypted ciphertext must throw an authentication error during decryption',
      () async {
        final encryptedBytes = await ImageEncryptionService.encryptImageBytes(
          sampleJpeg,
        );

        // Create a tampered copy by flipping a bit in the ciphertext (byte index 15, within ciphertext)
        final tamperedCiphertext = Uint8List.fromList(encryptedBytes);
        tamperedCiphertext[15] ^= 0x01; // flip 1 bit

        expect(
          () async => await ImageEncryptionService.decryptImageBytes(
            tamperedCiphertext,
          ),
          throwsA(isA<ImageAuthenticationException>()),
        );

        // Also tamper with the MAC authentication tag (last byte)
        final tamperedMac = Uint8List.fromList(encryptedBytes);
        tamperedMac[tamperedMac.length - 1] ^= 0x01;

        expect(
          () async => await ImageEncryptionService.decryptImageBytes(
            tamperedMac,
          ),
          throwsA(isA<ImageAuthenticationException>()),
        );

        // Also tamper with the Nonce (first byte)
        final tamperedNonce = Uint8List.fromList(encryptedBytes);
        tamperedNonce[0] ^= 0x01;

        expect(
          () async => await ImageEncryptionService.decryptImageBytes(
            tamperedNonce,
          ),
          throwsA(isA<ImageAuthenticationException>()),
        );
      },
    );

    test(
      '4. Feature flag disabled: encrypt and decrypt return original bytes untouched',
      () async {
        AppConfig.enableImageEncryption = false;

        final encrypted = await ImageEncryptionService.encryptImageBytes(
          sampleJpeg,
        );
        expect(encrypted, equals(sampleJpeg));

        final decrypted = await ImageEncryptionService.decryptImageBytes(
          sampleJpeg,
        );
        expect(decrypted, equals(sampleJpeg));
      },
    );

    test(
      '5. Edge cases: empty bytes and payloads < 28 bytes are handled safely',
      () async {
        final empty = Uint8List(0);
        expect(
          await ImageEncryptionService.encryptImageBytes(empty),
          equals(empty),
        );
        expect(
          await ImageEncryptionService.decryptImageBytes(empty),
          equals(empty),
        );

        // Less than 28 bytes (cannot be valid AES-GCM payload)
        final shortBytes = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
        final decryptedShort = await ImageEncryptionService.decryptImageBytes(
          shortBytes,
        );
        expect(decryptedShort, equals(shortBytes));
      },
    );

    test('6. Helper isPlainJpeg identifies JPEG header correctly', () {
      expect(
        ImageEncryptionService.isPlainJpeg(Uint8List.fromList([0xFF, 0xD8])),
        isTrue,
      );
      expect(
        ImageEncryptionService.isPlainJpeg(
          Uint8List.fromList([0xFF, 0xD8, 0x00, 0x01]),
        ),
        isTrue,
      );
      expect(
        ImageEncryptionService.isPlainJpeg(Uint8List.fromList([0xFF, 0x00])),
        isFalse,
      );
      expect(
        ImageEncryptionService.isPlainJpeg(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
        ),
        isFalse,
      ); // PNG
      expect(
        ImageEncryptionService.isPlainJpeg(Uint8List.fromList([0xFF])),
        isFalse,
      );
      expect(ImageEncryptionService.isPlainJpeg(Uint8List(0)), isFalse);
    });

    test(
      '7. Multiple encryptions produce unique nonces (randomized per encryption)',
      () async {
        final enc1 = await ImageEncryptionService.encryptImageBytes(sampleJpeg);
        final enc2 = await ImageEncryptionService.encryptImageBytes(sampleJpeg);

        expect(enc1, isNot(equals(enc2)));

        // Extract nonces (first 12 bytes)
        final nonce1 = enc1.sublist(0, 12);
        final nonce2 = enc2.sublist(0, 12);
        expect(nonce1, isNot(equals(nonce2)));

        // Both should decrypt to the exact same original JPEG
        final dec1 = await ImageEncryptionService.decryptImageBytes(enc1);
        final dec2 = await ImageEncryptionService.decryptImageBytes(enc2);
        expect(dec1, equals(sampleJpeg));
        expect(dec2, equals(sampleJpeg));
      },
    );
  });
}
