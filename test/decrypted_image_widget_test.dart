import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supervisorapp/core/config/app_config.dart';
import 'package:supervisorapp/core/security/image_encryption_service.dart';
import 'package:supervisorapp/widgets/decrypted_image_widget.dart';

void main() {
  // A minimal valid 1x1 pixel JPEG
  final Uint8List minimalJpeg = Uint8List.fromList([
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
    0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
    0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
    0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
    0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
    0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
    0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
    0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
    0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0A, 0x0B, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F,
    0x00, 0xBF, 0x00, 0xFF, 0xD9,
  ]);

  setUp(() {
    AppConfig.enableImageEncryption = true;
    DecryptedImageWidget.clearMemoryCache();
  });

  group('DecryptedImageWidget', () {
    testWidgets('Renders encrypted image bytes after transparent client-side decryption', (WidgetTester tester) async {
      final encryptedBytes = await ImageEncryptionService.encryptImageBytes(minimalJpeg);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DecryptedImageWidget(
              bytes: encryptedBytes,
              width: 100,
              height: 100,
            ),
          ),
        ),
      );

      // Pump to complete async decryption
      await tester.pumpAndSettle();

      // An Image widget should be rendered
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Renders legacy unencrypted JPEG bytes via backward compatibility', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DecryptedImageWidget(
              bytes: minimalJpeg,
              width: 80,
              height: 80,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('Displays fallback error icon when given invalid or missing image source', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DecryptedImageWidget(
              imageUrl: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Default error placeholder contains person icon
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });
  });
}
