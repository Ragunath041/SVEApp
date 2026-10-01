import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class DetectedFace {
  final Face? face;
  final bool wellPositioned;
  final bool hasGlare;
  final double glareScore;

  const DetectedFace({
    required this.face,
    required this.wellPositioned,
    this.hasGlare = false,
    this.glareScore = 0.0,
  });

  DetectedFace copyWith({
    Face? face,
    bool? wellPositioned,
    bool? hasGlare,
    double? glareScore,
  }) =>
      DetectedFace(
        face: face ?? this.face,
        wellPositioned: wellPositioned ?? this.wellPositioned,
        hasGlare: hasGlare ?? this.hasGlare,
        glareScore: glareScore ?? this.glareScore,
      );
}

