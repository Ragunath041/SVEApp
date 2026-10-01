import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:supervisorapp/widgets/footer.dart';
import 'package:supervisorapp/pages/ImageCropperPage.dart';

class AnswerSheetCaptureFlow extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String centreName;
  final String courseCode;
  final List<String>? existingImages;
  final bool singlePageOnly;
  final String? slotName;

  const AnswerSheetCaptureFlow({
    Key? key,
    required this.studentId,
    required this.studentName,
    required this.centreName,
    required this.courseCode,
    this.existingImages,
    this.singlePageOnly = false,
    this.slotName,
  }) : super(key: key);

  @override
  State<AnswerSheetCaptureFlow> createState() => _AnswerSheetCaptureFlowState();
}

class _AnswerSheetCaptureFlowState extends State<AnswerSheetCaptureFlow> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.existingImages != null && widget.existingImages!.isNotEmpty) {
        // If images already exist, replace THIS flow with selection/preview page
        // Use a slight delay to ensure the navigator is ready
        await Future.delayed(Duration(milliseconds: 100));
        if (!mounted) return;

        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AnswerSheetImageSelectionPage(
              capturedImages: widget.existingImages!,
              studentId: widget.studentId,
              studentName: widget.studentName,
              centreName: widget.centreName,
              courseCode: widget.courseCode,
              singlePageOnly: widget.singlePageOnly,
            ),
          ),
        );

        if (mounted) {
          Navigator.pop(context, result);
        }
      } else {
        // Open camera directly without showing any popup dialog
        _openCamera();
      }
    });
  }

  Future<void> _openCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("No camera available on this device."),
            backgroundColor: Colors.red.shade600,
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      if (!mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AnswerSheetCameraScreen(camera: cameras.first),
        ),
      );

      if (result != null && result is String) {
        if (!mounted) return;

        // Automatically open cropper after capture
        final croppedResult = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageCropperPage(image: XFile(result)),
          ),
        );

        if (croppedResult != null && croppedResult is XFile) {
          _showAcceptRejectDialog(croppedResult.path);
        } else {
          // If crop is cancelled, show dialog with original image
          _showAcceptRejectDialog(result);
        }
      } else {
        // User cancelled camera, go back
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Error accessing camera: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}",
          ),
          backgroundColor: Colors.red.shade600,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  void _showAcceptRejectDialog(String imagePath) {
    // Capture the widget's context before showing the dialog
    final widgetContext = context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                child: Image.file(
                  File(imagePath),
                  height: 300,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Delete the image and retake
                          File(imagePath).deleteSync();
                          Navigator.of(dialogContext).pop();
                          _openCamera();
                        },
                        icon: Icon(Icons.close, color: Colors.red, size: 18),
                        label: Text(
                          "Retake",
                          style: TextStyle(color: Colors.red, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.red.shade200),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final croppedResult = await Navigator.push(
                            dialogContext,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ImageCropperPage(image: XFile(imagePath)),
                            ),
                          );

                          if (croppedResult != null && croppedResult is XFile) {
                            if (!dialogContext.mounted) return;
                            Navigator.of(
                              dialogContext,
                            ).pop(); // Close current dialog
                            _showAcceptRejectDialog(
                              croppedResult.path,
                            ); // Show dialog with cropped image
                          }
                        },
                        icon: Icon(
                          Icons.crop,
                          color: Color(0xFF444CE7),
                          size: 18,
                        ),
                        label: Text(
                          "Crop",
                          style: TextStyle(
                            color: Color(0xFF444CE7),
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF444CE7).withOpacity(0.1),
                          elevation: 0,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: Color(0xFF444CE7).withOpacity(0.3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(dialogContext).pop(); // Close dialog

                          if (widget.singlePageOnly) {
                            // Immediately return single image (e.g. Front Page) without asking Add More
                            if (mounted) {
                              Navigator.of(widgetContext).pop([imagePath]);
                            }
                            return;
                          }

                          print(' Done button clicked.');
                          print(
                            ' widget.existingImages: ${widget.existingImages}',
                          );
                          print(
                            ' widget.existingImages length: ${widget.existingImages?.length ?? 'null'}',
                          );
                          print(' New image path: $imagePath');

                          // Combine existing images with the new one
                          List<String> combinedImages = [];
                          if (widget.existingImages != null &&
                              widget.existingImages!.isNotEmpty) {
                            combinedImages.addAll(widget.existingImages!);
                            print(
                              ' Adding to ${widget.existingImages!.length} existing images',
                            );
                          } else {
                            print(' No existing images to add');
                          }
                          combinedImages.add(imagePath);
                          print(' Total images now: ${combinedImages.length}');
                          print(' Combined images list: $combinedImages');

                          // Navigate to image selection page using the widget's context
                          if (!mounted) return;

                          final result = await Navigator.push(
                            widgetContext,
                            MaterialPageRoute(
                              builder: (context) =>
                                  AnswerSheetImageSelectionPage(
                                    capturedImages: combinedImages,
                                    studentId: widget.studentId,
                                    studentName: widget.studentName,
                                    centreName: widget.centreName,
                                    courseCode: widget.courseCode,
                                    singlePageOnly: widget.singlePageOnly,
                                  ),
                            ),
                          );

                          debugPrint(' Image Selection returned: $result');
                          debugPrint(' Result length: ${result?.length ?? 'null'}');

                          // Return the result to UploadPage using the widget's context
                          if (result != null && mounted && widgetContext.mounted) {
                            debugPrint(
                              ' Popping AnswerSheetCaptureFlow with ${result.length} images',
                            );
                            Navigator.of(widgetContext).pop(result);
                          }
                        },
                        icon: Icon(Icons.check, color: Colors.white),
                        label: Text(
                          "Done",
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt, size: 80, color: Colors.blue.shade200),
              SizedBox(height: 16),
              Text(
                "Preparing Camera...",
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        bottomNavigationBar: const AppFooter(),
      ),
    );
  }
}

// Camera Screen for Answer Sheets
class AnswerSheetCameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const AnswerSheetCameraScreen({Key? key, required this.camera})
    : super(key: key);

  @override
  State<AnswerSheetCameraScreen> createState() =>
      _AnswerSheetCameraScreenState();
}

class _AnswerSheetCameraScreenState extends State<AnswerSheetCameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      final directory = await getTemporaryDirectory();
      final imagePath = path.join(
        directory.path,
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final image = await _controller.takePicture();
      await File(image.path).copy(imagePath);

      if (!mounted) return;
      Navigator.pop(context, imagePath);
    } catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                Positioned.fill(child: CameraPreview(_controller)),
                Positioned(
                  top: 40,
                  left: 16,
                  child: IconButton(
                    icon: Icon(Icons.close, color: Colors.white, size: 32),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _takePicture,
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.blue, width: 4),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

// Image Selection Page for Answer Sheets
class AnswerSheetImageSelectionPage extends StatefulWidget {
  final List<String> capturedImages;
  final String studentId;
  final String studentName;
  final String centreName;
  final String courseCode;
  final bool singlePageOnly;

  const AnswerSheetImageSelectionPage({
    Key? key,
    required this.capturedImages,
    required this.studentId,
    required this.studentName,
    required this.centreName,
    required this.courseCode,
    this.singlePageOnly = false,
  }) : super(key: key);

  @override
  State<AnswerSheetImageSelectionPage> createState() =>
      _AnswerSheetImageSelectionPageState();
}

class _AnswerSheetImageSelectionPageState
    extends State<AnswerSheetImageSelectionPage> {
  late List<String> images;
  Set<int> selectedIndices = {};

  @override
  void initState() {
    super.initState();
    images = List.from(widget.capturedImages);
  }

  void _showAcceptRejectDialog(String imagePath) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                child: Image.file(
                  File(imagePath),
                  height: 300,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Delete the image and retake
                          if (File(imagePath).existsSync()) {
                            File(imagePath).deleteSync();
                          }
                          Navigator.of(dialogContext).pop();
                          _addMoreImages();
                        },
                        icon: const Icon(
                          Icons.close,
                          color: Colors.red,
                          size: 18,
                        ),
                        label: const Text(
                          "Retake",
                          style: TextStyle(color: Colors.red, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.red.shade200),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final croppedResult = await Navigator.push(
                            dialogContext,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ImageCropperPage(image: XFile(imagePath)),
                            ),
                          );

                          if (croppedResult != null && croppedResult is XFile) {
                            if (!dialogContext.mounted) return;
                            Navigator.of(
                              dialogContext,
                            ).pop(); // Close current dialog
                            _showAcceptRejectDialog(
                              croppedResult.path,
                            ); // Show dialog with cropped image
                          }
                        },
                        icon: const Icon(
                          Icons.crop,
                          color: Color(0xFF444CE7),
                          size: 18,
                        ),
                        label: const Text(
                          "Crop",
                          style: TextStyle(
                            color: Color(0xFF444CE7),
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(
                            0xFF444CE7,
                          ).withOpacity(0.1),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: const Color(0xFF444CE7).withOpacity(0.3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop(); // Close dialog
                          setState(() {
                            images.add(imagePath);
                          });
                        },
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: const Text(
                          "Done",
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addMoreImages() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnswerSheetCameraScreen(camera: cameras.first),
      ),
    );

    if (result != null && result is String) {
      if (!mounted) return;

      // Automatically open cropper after capture
      final croppedResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageCropperPage(image: XFile(result)),
        ),
      );

      if (croppedResult != null && croppedResult is XFile) {
        _showAcceptRejectDialog(croppedResult.path);
      } else {
        // If crop is cancelled, show dialog with original image
        _showAcceptRejectDialog(result);
      }
    }
  }

  void _deleteSelected() {
    if (selectedIndices.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("No images selected to delete.")));
      return;
    }

    setState(() {
      final indicesToRemove = selectedIndices.toList()
        ..sort((a, b) => b.compareTo(a));
      for (var index in indicesToRemove) {
        File(images[index]).deleteSync();
        images.removeAt(index);
      }
      selectedIndices.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Selected images deleted."),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _done() {
    if (images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please capture at least one image.")),
      );
      return;
    }

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Answer sheet images captured successfully!"),
        backgroundColor: Colors.green.shade600,
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );

    // Pop back to UploadPage (Student Details)
    // First pop: close this Image Selection Page and return images
    Navigator.of(context).pop(images);

    // Second pop: close AnswerSheetCaptureFlow and return images to UploadPage
    // This is handled by the AnswerSheetCaptureFlow's result handler
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("Select Images", style: TextStyle(color: Colors.black)),
        actions: [
          if (selectedIndices.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete, color: Colors.red),
              onPressed: _deleteSelected,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: images.isEmpty
                ? Center(child: Text("No images captured"))
                : GridView.builder(
                    padding: EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: images.length,
                    itemBuilder: (context, index) {
                      final isSelected = selectedIndices.contains(index);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              selectedIndices.remove(index);
                            } else {
                              selectedIndices.add(index);
                            }
                          });
                        },
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.blue
                                      : Colors.grey.shade300,
                                  width: isSelected ? 3 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(images[index]),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 8,
                              child: GestureDetector(
                                onTap: () async {
                                  final croppedResult = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ImageCropperPage(
                                        image: XFile(images[index]),
                                      ),
                                    ),
                                  );

                                  if (croppedResult != null &&
                                      croppedResult is XFile) {
                                    setState(() {
                                      images[index] = croppedResult.path;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.crop,
                                    size: 18,
                                    color: Color(0xFF444CE7),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 48,
                              child: GestureDetector(
                                onTap: () => _showFullScreenImage(
                                  context,
                                  images[index],
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.visibility,
                                    size: 18,
                                    color: Color(0xFF444CE7),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Colors.blue
                                      : Colors.white,
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.blue
                                        : Colors.grey.shade400,
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Add More Button (hidden if singlePageOnly is true)
                if (!widget.singlePageOnly) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addMoreImages,
                      icon: Icon(Icons.add_a_photo, size: 18),
                      label: Text(
                        "Add More",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                ],

                // Done Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _done,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF4CAF50),
                      padding: EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      "Done",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppFooter(),
    );
  }
}

void _showFullScreenImage(BuildContext context, String imagePath) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            "View Image",
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: Center(
          child: InteractiveViewer(
            panEnabled: true,
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.file(
              File(imagePath),
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    ),
  );
}
