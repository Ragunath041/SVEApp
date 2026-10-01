import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:geolocator/geolocator.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:supervisorapp/Services/StorageService.dart';
import 'package:supervisorapp/Services/attendance/student_attendance_service.dart';
import 'package:intl/intl.dart';

class CameraCaptureFlow extends StatefulWidget {
  final Map<String, String> formData;

  const CameraCaptureFlow({super.key, required this.formData});

  @override
  State<CameraCaptureFlow> createState() => _CameraCaptureFlowState();
}


class _CameraCaptureFlowState extends State<CameraCaptureFlow> {
  @override
  void initState() {
    super.initState();
    // Show start capture dialog immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showStartCaptureDialog();
    });
  }

  void _showStartCaptureDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.camera_alt,
                  size: 64,
                  color: Color.fromARGB(255, 68, 76, 231),
                ),
                SizedBox(height: 16),
                Text(
                  "Capture Incident Photos",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  "Tap the button below to photograph evidence documenting the incident.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openCamera();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(255, 68, 76, 231),
                      padding: EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      "Start Camera",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  child: Text("Cancel"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCamera() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("No camera available on this device."),
            backgroundColor: Colors.red.shade600,
          ),
        );
        Navigator.of(context).pop(); // Go back to incident report
        return;
      }

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CameraScreen(camera: cameras.first),
        ),
      );

      if (!mounted) return;

      if (result != null && result is String) {
        _showAcceptRejectDialog(result);
      } else {
        // User cancelled camera, go back
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Failed to access camera. Please check camera permissions in Settings.",
          ),
          backgroundColor: Colors.red.shade600,
        ),
      );
      debugPrint("Failed to access camera: ${e.toString()}");
      Navigator.of(context).pop(); // Go back to incident report
    }
  }

  void _showAcceptRejectDialog(String imagePath) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
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
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Delete the image and retake
                          File(imagePath).deleteSync();
                          Navigator.of(context).pop();
                          _openCamera();
                        },
                        icon: Icon(Icons.close, color: Colors.red),
                        label: Text(
                          "Retake",
                          style: TextStyle(color: Colors.red),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.red.shade200),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          final backResult = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ImageSelectionPage(
                                capturedImages: [imagePath],
                                formData: widget.formData,
                              ),
                            ),
                          );
                          if (backResult == 'back_to_camera') {
                            if (mounted) {
                              try {
                                File(imagePath).deleteSync();
                              } catch (e) {
                                print("Error deleting image: $e");
                              }
                              _openCamera();
                            }
                          }
                        },
                        icon: Icon(Icons.check, color: Colors.white),
                        label: Text(
                          "Accept",
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
        // Allow back navigation
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

// Camera Screen
class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({Key? key, required this.camera}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
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
      debugPrint('Failed taking picture: $e');
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

// Image Selection Page with Checkboxes
class ImageSelectionPage extends StatefulWidget {
  final List<String> capturedImages;
  final Map<String, String> formData;

  const ImageSelectionPage({
    Key? key,
    required this.capturedImages,
    required this.formData,
  }) : super(key: key);

  @override
  State<ImageSelectionPage> createState() => _ImageSelectionPageState();
}

class _ImageSelectionPageState extends State<ImageSelectionPage> {
  late List<String> images;
  Set<int> selectedIndices = {};

  @override
  void initState() {
    super.initState();
    images = List.from(widget.capturedImages);
  }

  Future<void> _addMoreImages() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(camera: cameras.first),
      ),
    );

    if (!mounted) return;

    if (result != null && result is String) {
      setState(() {
        images.add(result);
      });
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
      // Delete files and remove from list
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
        SnackBar(content: Text("Please capture at least one photo.")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            FinalReviewPage(capturedImages: images, formData: widget.formData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, 'back_to_camera');
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context, 'back_to_camera'),
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
                  ? Center(child: Text("No images captured."))
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
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _addMoreImages,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade50,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Colors.blue.shade200),
                        ),
                      ),
                      child: Text(
                        "Add More",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _done,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF2196F3),
                        elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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
      ),
    );
  }
}

// Final Review Page with Swipeable Images and Form Data
class FinalReviewPage extends StatefulWidget {
  final List<String> capturedImages;
  final Map<String, String> formData;

  const FinalReviewPage({
    Key? key,
    required this.capturedImages,
    required this.formData,
  }) : super(key: key);

  @override
  State<FinalReviewPage> createState() => _FinalReviewPageState();
}

class _FinalReviewPageState extends State<FinalReviewPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  String _lat = "Fetching...";
  String _long = "Fetching...";

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _lat = "Disabled";
          _long = "Disabled";
        });
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _lat = "Denied";
            _long = "Denied";
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _lat = "Denied";
          _long = "Denied";
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _lat = position.latitude.toStringAsFixed(6);
          _long = position.longitude.toStringAsFixed(6);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lat = "Error";
          _long = "Error";
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
          onPressed: () {
            // Go back to incident report page
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          "Review Incident Report",
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Swipeable Image Carousel
            Container(
              height: 300,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemCount: widget.capturedImages.length,
                    itemBuilder: (context, index) {
                      return Image.file(
                        File(widget.capturedImages[index]),
                        fit: BoxFit.cover,
                        width: double.infinity,
                      );
                    },
                  ),
                  // Page Indicator
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        widget.capturedImages.length,
                        (index) => Container(
                          margin: EdgeInsets.symmetric(horizontal: 4),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentPage == index
                                ? Colors.blue
                                : Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Image Counter
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "${_currentPage + 1}/${widget.capturedImages.length}",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 24),

            // Form Data Display
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Incident Details",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow(
                          "Student ID",
                          widget.formData['studentId'] ?? 'N/A',
                          isFirst: true,
                        ),
                        _buildDetailRow(
                          "Student Name",
                          widget.formData['studentName'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          "Course Code",
                          widget.formData['courseCode'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          "Course Name",
                          widget.formData['courseName'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          "Centre Name",
                          widget.formData['centreName'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          "Nature of UFM",
                          widget.formData['ufm'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          "Types of Offence",
                          widget.formData['offence'] ?? 'N/A',
                        ),
                        _buildDetailRow(
                          "GPS Details",
                          "Latitude: $_lat \n Longitude: $_long",
                          isLast: true,
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 16),
                  Text(
                    "Description",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    height: 120,
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        widget.formData['description'] ??
                            'No description provided',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // Handle final submission
                        _handleSubmit();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF2196F3),
                        elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        "Submit Incident Report",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppFooter(),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            padding: EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color.fromARGB(255, 68, 76, 231),
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  'Uploading Incident Report...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Import StorageService at the top of the file if not already imported
      final storageService = StorageService();

      // Add GPS coordinates to form data
      final enrichedFormData = {
        ...widget.formData,
        'latitude': _lat,
        'longitude': _long,
      };

      // Upload incident report to S3
      final result = await storageService.uploadIncidentReport(
        formData: enrichedFormData,
        photosPaths: widget.capturedImages,
      );

      storageService.dispose();

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      if (result['success'] == true) {
        // Mark student's attendance as incident (99:99:99) in DynamoDB
        try {
          final today = DateFormat('dd-MM-yyyy').format(DateTime.now());
          await DynamoDBAttendanceService.markAsIncident(
            bitsId: widget.formData['studentId'] ?? '',
            courseCode: widget.formData['courseCode'] ?? '',
            examDate: today,
            session: widget.formData['session'],
          );
          print(' Student attendance marked as incident (99:99:99)');
        } catch (dbError) {
          print(' Failed to update incident status in DynamoDB: $dbError');
        }

        // Show success message at top
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Incident report uploaded successfully (${result['photosUploaded']}/${result['totalPhotos']} photos).",
              ),
              backgroundColor: Colors.green.shade600,
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }

        // Navigate back to dashboard
        await Future.delayed(Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(); // Pop FinalReviewPage
          Navigator.of(context).pop(); // Pop ImageSelectionPage
          Navigator.of(context).pop(); // Pop CameraCaptureFlow
        }
      } else {
        // Show error message at top
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Upload failed: ${result['error'] ?? 'Please check your connection and try again.'}",
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) Navigator.pop(context);

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Upload error: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}",
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }
}
