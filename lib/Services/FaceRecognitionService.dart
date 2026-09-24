import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:supervisorapp/Services/storage/s3_transfer_helper.dart';

class FaceRecognitionServiceEnhanced {
  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;
  static Interpreter? _interpreter;
  static FaceDetector? _faceDetector;

  static const String _embeddingKey = 'face_embedding_';
  static const int _embeddingSize = 192;
  static const int _inputSize = 112;

  static const String _bucketName = 'bits-supervisorapp';

  static FaceDetectorOptions _getDetectorOptions() {
    if (Platform.isIOS) {
      // iOS OPTIMIZED CONFIG - More lenient for better detection
      debugPrint(
        ' Configuring iOS Face Detector (Fast mode, minFaceSize: 0.01)',
      );
      return FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: true, // Enable for better face detection on iOS
        enableClassification: false,
        enableTracking: false,
        minFaceSize: 0.01, // Lower threshold for iOS cameras
        performanceMode: FaceDetectorMode.fast,
      );
    } else {
      // ANDROID ACCURATE CONFIG
      debugPrint(' Configuring Android Face Detector (Accurate mode)');
      return FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: true,
        enableClassification: false,
        enableTracking: false,
        minFaceSize: 0.05,
        performanceMode: FaceDetectorMode.accurate,
      );
    }
  }

  static Future<void> _ensureInitialized() async {
    if (_isInitialized && _interpreter != null) return;
    await initialize();
  }

  static Future<void> initialize() async {
    try {
      debugPrint(' Initializing Enhanced MobileFaceNet service...');

      // Initialize Detector
      _faceDetector = FaceDetector(options: _getDetectorOptions());

      // Initialize TFLite interpreter
      await _initializeInterpreter();

      _isInitialized = true;
      debugPrint(' MobileFaceNet service initialized successfully!');
    } catch (e) {
      debugPrint(' Error initializing MobileFaceNet service: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  static Future<void> _initializeInterpreter() async {
    try {
      const String modelPath = 'assets/models/mobilefacenet.tflite';
      debugPrint(' Loading TFLite model from: $modelPath');

      // 1. Force CPU on iOS RELEASE builds to avoid silent GPU delegate crashes
      if (Platform.isIOS && kReleaseMode) {
        debugPrint(
          ' iOS Release Mode: Using CPU-only (avoiding GPU delegate issues)',
        );
        _interpreter = await Interpreter.fromAsset(
          modelPath,
          options: InterpreterOptions(), // CPU ONLY
        );
        debugPrint(' CPU-based TFLite Interpreter initialized (iOS Release)');
      }
      // 2. Web fallback
      else if (kIsWeb) {
        debugPrint(' Web Mode: Using CPU-only');
        _interpreter = await Interpreter.fromAsset(
          modelPath,
          options: InterpreterOptions(),
        );
        debugPrint(' Web-based TFLite Interpreter initialized');
      }
      // 3. Attempt GPU for Android & iOS Debug builds
      else {
        try {
          debugPrint(' Attempting GPU acceleration...');
          final gpuOptions = InterpreterOptions();
          final gpuDelegate = GpuDelegate();
          gpuOptions.addDelegate(gpuDelegate);

          _interpreter = await Interpreter.fromAsset(
            modelPath,
            options: gpuOptions,
          );
          debugPrint(' GPU acceleration enabled for MobileFaceNet');
        } catch (gpuError) {
          debugPrint(' GPU delegate failed, falling back to CPU: $gpuError');

          // CPU Fallback
          final cpuOptions = InterpreterOptions();
          _interpreter = await Interpreter.fromAsset(
            modelPath,
            options: cpuOptions,
          );
          debugPrint(' CPU-based TFLite Interpreter initialized');
        }
      }

      if (_interpreter == null) {
        throw Exception('Failed to initialize TFLite interpreter');
      }

      final inputShape = _interpreter!.getInputTensor(0).shape;
      debugPrint(' Model loaded successfully, input shape: $inputShape');
    } catch (e) {
      debugPrint(' Failed to initialize TFLite Interpreter: $e');
      rethrow;
    }
  }

  /// Generate Embedding from local image file path
  static Future<String?> generateEmbedding(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    return await generateEmbeddingFromInputImage(inputImage);
  }

  /// Generate Embedding from raw bytes (matches service.dart)
  static Future<String?> generateEmbeddingFromBytes(
    Uint8List imageBytes,
  ) async {
    await _ensureInitialized();
    if (!_isInitialized) {
      debugPrint(' FaceRecognitionService not initialized');
      return null;
    }

    try {
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/temp_face_bytes_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(imageBytes);

      try {
        final inputImage = InputImage.fromFilePath(tempFile.path);
        return await generateEmbeddingFromInputImage(inputImage);
      } finally {
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (e) {
          debugPrint(' Error deleting temp file: $e');
        }
      }
    } catch (e) {
      debugPrint(' Error generating embedding from bytes: $e');
      return null;
    }
  }

  /// Generate Embedding with exhaustive rotation for better reliability (especially on iOS)
  static Future<String?> generateEmbeddingFromInputImage(
    InputImage inputImage,
  ) async {
    await _ensureInitialized();
    if (!_isInitialized) {
      debugPrint(' FaceRecognitionService not initialized');
      return null;
    }

    try {
      final String originalPath = inputImage.filePath!;
      final File imageFile = File(originalPath);
      final Uint8List imageBytes = await imageFile.readAsBytes();
      img.Image? baseImage = img.decodeImage(imageBytes);

      if (baseImage == null) {
        debugPrint(' Failed to decode base image');
        return null;
      }

      // Pre-resize base image to 512x512 with linear interpolation
      baseImage = img.copyResize(
        baseImage,
        width: 512,
        height: 512,
        interpolation: img.Interpolation.linear,
        maintainAspect: true,
      );

      // AUTO-FIX EXIF ORIENTATION
      debugPrint(' Applying EXIF orientation correction...');
      baseImage = img.bakeOrientation(baseImage);

      List<Face> faces = [];
      img.Image processedImage = baseImage;
      int successfulAngle = -1;

      if (Platform.isIOS) {
        // ==========================================
        // SPECIALIZED iOS PATH: "Bake-First" Strategy
        // ==========================================
        final List<int> iosAngles = [0, 270, 90, 180];

        for (int angle in iosAngles) {
          img.Image currentRotation = (angle == 0)
              ? baseImage
              : img.copyRotate(baseImage, angle: angle);

          final tempDir = Directory.systemTemp;
          final tempFile = File('${tempDir.path}/ios_rot_$angle.jpg');
          await tempFile.writeAsBytes(img.encodeJpg(currentRotation));
          final attemptImage = InputImage.fromFilePath(tempFile.path);

          try {
            debugPrint(
              '  [iOS Detection] Trying angle $angle° (baked pixels)...',
            );
            faces = await _faceDetector!.processImage(attemptImage);

            if (faces.isNotEmpty) {
              Face? bestFace = _selectBestFace(
                faces,
                currentRotation.width,
                currentRotation.height,
              );
              if (bestFace != null) {
                debugPrint('  ✅ [iOS] Face found at $angle°');
                successfulAngle = angle;
                processedImage = currentRotation;
                break;
              }
            }
          } finally {
            if (await tempFile.exists()) await tempFile.delete();
          }
        }
      } else {
        // ==========================================
        // ANDROID PATH: Exhaustive Rotation (Stable)
        // ==========================================
        final List<int> androidAngles = [0, 270, 90, 180];

        for (int angle in androidAngles) {
          InputImage currentAttemptImage;
          img.Image currentRotation;

          currentRotation = (angle == 0)
              ? baseImage
              : img.copyRotate(baseImage, angle: angle);

          final tempDir = Directory.systemTemp;
          final tempFile = File('${tempDir.path}/rot_$angle.jpg');
          await tempFile.writeAsBytes(img.encodeJpg(currentRotation));
          currentAttemptImage = InputImage.fromFilePath(tempFile.path);

          try {
            debugPrint(
              '  [Android Detection] Trying angle $angle° (baked pixels)...',
            );
            faces = await _faceDetector!.processImage(currentAttemptImage);

            if (faces.isNotEmpty) {
              Face? bestFace = _selectBestFace(
                faces,
                currentRotation.width,
                currentRotation.height,
              );
              if (bestFace != null) {
                debugPrint('  ✅ [Android] Face found at $angle°');
                successfulAngle = angle;
                processedImage = currentRotation;
                break;
              }
            }
          } finally {
            if (await tempFile.exists()) await tempFile.delete();
          }
        }
      }

      if (successfulAngle == -1 || faces.isEmpty) {
        debugPrint(
          ' FAIL: No suitable faces detected after trying all rotations',
        );
        return null;
      }

      Face? finalBestFace = _selectBestFace(
        faces,
        processedImage.width,
        processedImage.height,
      );

      if (finalBestFace == null) {
        debugPrint(' FAIL: Best face selection returned null');
        return null;
      }

      final embedding = await _extractMobileFaceNetEmbedding(
        processedImage,
        finalBestFace,
      );

      if (embedding == null) {
        debugPrint(' Failed to generate MobileFaceNet embedding');
        return null;
      }

      return encodeEmbedding(embedding);
    } catch (e) {
      debugPrint(' Error in generateEmbedding: $e');
      return null;
    }
  }

  static Face? _selectBestFace(
    List<Face> faces,
    int imageWidth,
    int imageHeight,
  ) {
    Face? bestFace;
    double bestScore = 0.0;

    for (final face in faces) {
      final bbox = face.boundingBox;
      final area = bbox.width * bbox.height;

      // Check distance (ratio of face width to frame width)
      final double faceWidthRatio = bbox.width / imageWidth;
      const double minFaceRatio = 0.15;
      const double maxFaceRatio = 0.85;

      if (faceWidthRatio < minFaceRatio) {
        debugPrint(
          ' Face too far: ratio = ${faceWidthRatio.toStringAsFixed(3)} (min: $minFaceRatio)',
        );
        continue;
      }

      if (faceWidthRatio > maxFaceRatio) {
        debugPrint(
          ' Face too close: ratio = ${faceWidthRatio.toStringAsFixed(3)} (max: $maxFaceRatio)',
        );
        continue;
      }

      // Face quality checks - VERY lenient for mobile cameras (especially iOS)
      if (area < 2000) {
        debugPrint(' Face too small: area = $area (minimum: 2000)');
        continue;
      }

      // Face angle requirements - more tolerant
      final yAngle = face.headEulerAngleY?.abs() ?? 0.0;
      final xAngle = face.headEulerAngleX?.abs() ?? 0.0;
      final zAngle = face.headEulerAngleZ?.abs() ?? 0.0;

      bool isAngleValid = Platform.isIOS
          ? (yAngle <= 60.0)
          : (yAngle <= 60.0 && zAngle <= 40.0);
      if (!isAngleValid) {
        debugPrint(
          ' Face angle too extreme: Y=$yAngle, X=$xAngle, Z=$zAngle (max: Y=60, Z=40)',
        );
        continue;
      }

      // Enhanced quality scoring
      final totalAngle = Platform.isIOS
          ? (yAngle + xAngle)
          : (yAngle + xAngle + zAngle);
      final angleScore = math.max(0.0, 1.0 - (totalAngle) / 120.0);
      final sizeScore = math.min(area / 15000.0, 1.0);
      final landmarkScore = face.landmarks.isNotEmpty
          ? math.min(face.landmarks.length / 8.0, 1.0)
          : 0.6; // More lenient landmark scoring

      final faceAspectRatio = face.boundingBox.width / face.boundingBox.height;
      final aspectRatioScore = (faceAspectRatio > 0.6 && faceAspectRatio < 1.6)
          ? 1.0
          : 0.7; // More lenient aspect ratio

      // Center position score
      final centerX = face.boundingBox.left + face.boundingBox.width / 2;
      final centerY = face.boundingBox.top + face.boundingBox.height / 2;
      final imageCenterX = imageWidth / 2.0;
      final imageCenterY = imageHeight / 2.0;
      final distanceFromCenter = math.sqrt(
        math.pow(centerX - imageCenterX, 2) +
            math.pow(centerY - imageCenterY, 2),
      );
      final centerScore = math.max(
        0.0,
        1.0 - distanceFromCenter / (math.min(imageWidth, imageHeight) * 0.5),
      );

      // Weighted quality score with more emphasis on size and less on strict requirements
      final qualityScore =
          (sizeScore * 0.4) +
          (angleScore * 0.25) +
          (landmarkScore * 0.2) +
          (aspectRatioScore * 0.1) +
          (centerScore * 0.05);

      debugPrint(
        ' Face quality score: ${qualityScore.toStringAsFixed(3)} (size:${sizeScore.toStringAsFixed(2)}, angle:${angleScore.toStringAsFixed(2)}, landmarks:${landmarkScore.toStringAsFixed(2)})',
      );

      if (qualityScore > bestScore) {
        bestScore = qualityScore;
        bestFace = face;
      }
    }

    // Very lenient quality threshold for iOS compatibility
    if (bestFace == null || bestScore < 0.2) {
      debugPrint(
        ' No suitable quality face found (best score: ${bestScore.toStringAsFixed(3)}, required: 0.2)',
      );
      return null;
    }

    debugPrint(
      ' Selected high-quality face with score: ${bestScore.toStringAsFixed(3)}',
    );
    return bestFace;
  }

  static Future<List<double>?> _extractMobileFaceNetEmbedding(
    img.Image image,
    Face face,
  ) async {
    await _ensureInitialized();
    try {
      if (_interpreter == null) return null;

      final faceRegion = _cropFaceRegion(image, face);

      img.Image inputImage;
      if (Platform.isIOS) {
        // iOS Intermediate Preprocessing (160x160)
        final resized160 = img.copyResize(
          faceRegion,
          width: 160,
          height: 160,
          interpolation: img.Interpolation.linear,
          maintainAspect: true,
        );
        inputImage = img.copyResize(
          resized160,
          width: 112,
          height: 112,
          interpolation: img.Interpolation.linear,
          maintainAspect: true,
        );
      } else {
        inputImage = img.copyResize(
          faceRegion,
          width: 112,
          height: 112,
          interpolation: img.Interpolation.linear,
          maintainAspect: true,
        );
      }

      // Diagnostic log to check pixel channel ranges (0..1 vs 0..255)
      if (inputImage.width > 0 && inputImage.height > 0) {
        final p = inputImage.getPixel(0, 0);
        debugPrint(
          ' [FaceRecognition] First pixel values: R=${p.r}, G=${p.g}, B=${p.b}',
        );
      }

      final input = List.generate(
        1,
        (_) => List.generate(
          112,
          (_) => List.generate(112, (_) => List.filled(3, 0.0)),
        ),
      );

      for (int y = 0; y < 112; y++) {
        for (int x = 0; x < 112; x++) {
          final p = inputImage.getPixel(x, y);
          input[0][y][x][0] = ((p.r.toDouble()) - 127.5) / 127.5;
          input[0][y][x][1] = ((p.g.toDouble()) - 127.5) / 127.5;
          input[0][y][x][2] = ((p.b.toDouble()) - 127.5) / 127.5;
        }
      }

      final output = List.generate(1, (_) => List.filled(_embeddingSize, 0.0));
      _interpreter!.run(input, output);

      final emb = output[0].cast<double>().toList();

      // Diagnostic log of the raw output embedding
      debugPrint(
        ' [FaceRecognition] Raw Output Embedding (first 5): ${emb.take(5).toList()}',
      );

      double norm = math.sqrt(
        emb.fold(0.0, (prev, element) => prev + element * element),
      );

      if (norm > 0) {
        for (int i = 0; i < emb.length; i++) emb[i] /= norm;
      }
      return emb;
    } catch (e) {
      debugPrint(' Error in inference: $e');
      return null;
    }
  }

  static img.Image _cropFaceRegion(img.Image image, Face face) {
    final bbox = face.boundingBox;

    // 1. Find the center of the detected face
    final double centerX = bbox.left + (bbox.width / 2);
    final double centerY = bbox.top + (bbox.height / 2);

    // 2. Add padding (e.g., 10% padding on each side for tighter face focus)
    final double paddedWidth = bbox.width * 1.2;
    final double paddedHeight = bbox.height * 1.2;

    // 3. Force it into a perfect square by taking the larger side
    final double sideLength = math.max(paddedWidth, paddedHeight);

    // 4. Calculate crop coordinates (centering the square)
    int x = (centerX - (sideLength / 2)).round();
    int y = (centerY - (sideLength / 2)).round();

    // 5. Shift crop box inward if it overflows screen boundaries
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x + sideLength.round() > image.width) {
      x = image.width - sideLength.round();
    }
    if (y + sideLength.round() > image.height) {
      y = image.height - sideLength.round();
    }

    // 6. Safe clamp if side length exceeds total image dimensions
    final int finalSide = math.min(
      sideLength.round(),
      math.min(image.width, image.height),
    );
    final int finalX = math.max(0, math.min(x, image.width - finalSide));
    final int finalY = math.max(0, math.min(y, image.height - finalSide));

    return img.copyCrop(
      image,
      x: finalX,
      y: finalY,
      width: finalSide,
      height: finalSide,
    );
  }

  // --- Utility & Storage Methods ---

  static String aggregateEmbeddings(List<String> embeddings) {
    if (embeddings.isEmpty) {
      debugPrint(' No embeddings to aggregate');
      return '';
    }

    if (embeddings.length == 1) {
      debugPrint(' Single embedding, no aggregation needed');
      return embeddings.first;
    }

    debugPrint(
      ' Aggregating ${embeddings.length} embeddings into single template',
    );
    final decodedEmbeddings = embeddings
        .map((e) => decodeEmbedding(e))
        .toList();

    if (decodedEmbeddings.any((emb) => emb.isEmpty)) {
      debugPrint(' Some embeddings failed to decode');
      final validEmbeddings = decodedEmbeddings
          .where((emb) => emb.isNotEmpty)
          .toList();
      if (validEmbeddings.isEmpty) return '';

      debugPrint(
        ' Using ${validEmbeddings.length} valid embeddings out of ${embeddings.length}',
      );
    }

    final validEmbeddings = decodedEmbeddings
        .where((emb) => emb.isNotEmpty)
        .toList();
    final dimensions = validEmbeddings.first.length;

    // Element-wise average with equal weighting
    final aggregated = List.filled(dimensions, 0.0);
    for (int i = 0; i < dimensions; i++) {
      double sum = 0.0;
      for (final embedding in validEmbeddings) {
        sum += embedding[i];
      }
      aggregated[i] = sum / validEmbeddings.length;
    }

    // L2 normalize the aggregated embedding
    double norm = math.sqrt(
      aggregated.map((x) => x * x).reduce((a, b) => a + b),
    );
    if (norm > 0) {
      for (int i = 0; i < aggregated.length; i++) {
        aggregated[i] /= norm;
      }
    }

    debugPrint(
      ' Successfully aggregated ${validEmbeddings.length} embeddings into normalized template',
    );
    return encodeEmbedding(aggregated);
  }

  static String encodeEmbedding(List<double> embedding) {
    final bytes = <int>[];
    for (final value in embedding) {
      final buffer = ByteData(8)..setFloat64(0, value, Endian.little);
      bytes.addAll(buffer.buffer.asUint8List());
    }
    return base64Encode(bytes);
  }

  static List<double> decodeEmbedding(String str) {
    try {
      final bytes = base64Decode(str);
      final embedding = <double>[];
      for (int i = 0; i < bytes.length; i += 8) {
        if (i + 7 < bytes.length) {
          final buffer = ByteData(8);
          for (int j = 0; j < 8; j++) buffer.setUint8(j, bytes[i + j]);
          embedding.add(buffer.getFloat64(0, Endian.little));
        }
      }
      return embedding;
    } catch (e) {
      debugPrint(' Error decoding embedding: $e');
      return [];
    }
  }

  static Future<void> saveEmbedding(String id, String embedding) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_embeddingKey + id, embedding);

    try {
      final jsonData = jsonEncode({
        'supervisor_id': id,
        'embedding': embedding,
        'created_at': DateTime.now().toIso8601String(),
      });
      final success = await S3Helper.upload(
        bucket: _bucketName,
        key: 'Supervisor-details/$id/face_embedding.json',
        body: utf8.encode(jsonData),
        contentType: 'application/json',
      );
      if (!success) {
        throw Exception('S3 upload returned false.');
      }
    } catch (e) {
      debugPrint(' S3 save failed: $e');
    }
  }

  static Future<String?> loadEmbedding(String id) async {
    final prefs = SharedPreferencesAsync();
    String? encoded = await prefs.getString(_embeddingKey + id);
    if (encoded == null) {
      try {
        final embeddingBytes = await S3Helper.download(
          bucket: _bucketName,
          key: 'Supervisor-details/$id/face_embedding.json',
        );
        if (embeddingBytes != null) {
          final data = jsonDecode(utf8.decode(embeddingBytes));
          encoded = data['embedding'];
          if (encoded != null) {
            await prefs.setString(_embeddingKey + id, encoded);
          }
        }
      } catch (_) {}
    }
    return encoded;
  }

  static double compareFaces(String e1, String e2) {
    try {
      final emb1 = decodeEmbedding(e1);
      final emb2 = decodeEmbedding(e2);

      if (emb1.isEmpty || emb2.isEmpty) {
        debugPrint(' Empty embeddings: ${emb1.length} vs ${emb2.length}');
        return 0.0;
      }

      if (emb1.length != emb2.length) {
        debugPrint(
          ' Embedding length mismatch: ${emb1.length} vs ${emb2.length}',
        );
        return 0.0;
      }

      // Log the first 5 elements of the compared embeddings
      debugPrint(' [FaceCompare] emb1 (first 5): ${emb1.take(5).toList()}');
      debugPrint(' [FaceCompare] emb2 (first 5): ${emb2.take(5).toList()}');

      final cosineSimilarity = _calculateCosineSimilarity(emb1, emb2);
      debugPrint(' Cosine similarity: ${cosineSimilarity.toStringAsFixed(4)}');
      return cosineSimilarity.clamp(0.0, 1.0);
    } catch (e) {
      debugPrint(' Error calculating similarity: $e');
      return 0.0;
    }
  }

  static double _calculateCosineSimilarity(
    List<double> emb1,
    List<double> emb2,
  ) {
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < emb1.length; i++) {
      dotProduct += emb1[i] * emb2[i];
      norm1 += emb1[i] * emb1[i];
      norm2 += emb2[i] * emb2[i];
    }

    if (norm1 == 0.0 || norm2 == 0.0) return 0.0;

    final cosineSimilarity = dotProduct / (math.sqrt(norm1) * math.sqrt(norm2));
    return (cosineSimilarity + 1.0) / 2.0; // Convert to 0-1 range
  }

  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _faceDetector?.close();
    _faceDetector = null;
    _isInitialized = false;
    debugPrint(' FaceRecognitionService disposed');
  }
}
