import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:supervisorapp/pages/answer_sheet_capture.dart';
import 'package:supervisorapp/pages/ImageCropperPage.dart';
import 'package:supervisorapp/Services/StorageService.dart';

class AttendanceReportUploadPage extends StatefulWidget {
  final String centre;
  final String supervisorId;

  const AttendanceReportUploadPage({
    Key? key,
    required this.centre,
    required this.supervisorId,
  }) : super(key: key);

  @override
  State<AttendanceReportUploadPage> createState() =>
      _AttendanceReportUploadPageState();
}

class _AttendanceReportUploadPageState
    extends State<AttendanceReportUploadPage> {
  final List<String> _images = [];
  final Set<int> _selectedIndices = {};
  bool _isUploading = false;

  Future<void> _capturePage() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No camera available on this device."),
            backgroundColor: Colors.red,
          ),
        );
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

        // Open cropper automatically
        final croppedResult = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageCropperPage(image: XFile(result)),
          ),
        );

        String finalPath = (croppedResult != null && croppedResult is XFile)
            ? croppedResult.path
            : result;

        setState(() {
          _images.add(finalPath);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error accessing camera: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deleteSelected() {
    if (_selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No pages selected to delete.")),
      );
      return;
    }

    setState(() {
      final indicesToRemove = _selectedIndices.toList()
        ..sort((a, b) => b.compareTo(a));
      for (var index in indicesToRemove) {
        try {
          final file = File(_images[index]);
          if (file.existsSync()) {
            file.deleteSync();
          }
        } catch (e) {
          print("Error deleting image file: $e");
        }
        _images.removeAt(index);
      }
      _selectedIndices.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Selected pages deleted."),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _deleteSingleImage(int index) {
    setState(() {
      try {
        final file = File(_images[index]);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        print("Error deleting image file: $e");
      }
      _images.removeAt(index);
      _selectedIndices.remove(index);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Page deleted."),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _handleUpload() async {
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please capture at least one page before uploading."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(
                  color: Color.fromARGB(255, 68, 76, 231),
                ),
                SizedBox(height: 24),
                Text(
                  'Uploading attendance report...',
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
      final now = DateTime.now();
      String session = "FN";
      final hour = now.hour;
      if (hour >= 13 && hour < 18) {
        session = "AN";
      } else if (hour >= 18) {
        session = "EN";
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(now);

      final storageService = StorageService();
      final uploadResult = await storageService.uploadAttendanceSheetImages(
        imagePaths: _images,
        date: dateStr,
        session: session,
        centre: widget.centre,
      );
      storageService.dispose();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }

      if (uploadResult['success'] == true) {
        // Delete files from disk after successful upload
        for (var imagePath in _images) {
          try {
            final file = File(imagePath);
            if (file.existsSync()) {
              file.deleteSync();
            }
          } catch (e) {
            print("Failed to delete temp file: $e");
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                uploadResult['message'] ??
                    "Attendance sheets uploaded successfully!",
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // Pop back to dashboard
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Upload failed: ${uploadResult['error'] ?? 'Please try again.'}"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload error: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
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
              "View Page",
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Upload Attendance Report",
          style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedIndices.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _deleteSelected,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _images.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment_turned_in_outlined, size: 80, color: Colors.blue.shade200),
                        const SizedBox(height: 16),
                        Text(
                          "No pages captured yet.",
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Click the capture button to start.",
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _images.length,
                    itemBuilder: (context, index) {
                      final isSelected = _selectedIndices.contains(index);
                      final imagePath = _images[index];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedIndices.remove(index);
                            } else {
                              _selectedIndices.add(index);
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
                                  File(imagePath),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                            ),
                            // Selection Indicator Circle
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? Colors.blue : Colors.white.withOpacity(0.8),
                                  border: Border.all(
                                    color: isSelected ? Colors.blue : Colors.grey.shade400,
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                            // Action buttons at the bottom of the card
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Row(
                                children: [
                                  // View Button
                                  GestureDetector(
                                    onTap: () => _showFullScreenImage(context, imagePath),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.9),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.visibility,
                                        size: 14,
                                        color: Color(0xFF444CE7),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Delete Button
                                  GestureDetector(
                                    onTap: () => _deleteSingleImage(index),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.9),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.delete,
                                        size: 14,
                                        color: Colors.red,
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
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _capturePage,
                    icon: const Icon(Icons.add_a_photo, size: 18),
                    label: const Text(
                      "Capture Page",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade50,
                      foregroundColor: Colors.blue.shade700,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.blue.shade200),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _handleUpload,
                    icon: const Icon(Icons.upload, size: 18),
                    label: const Text(
                      "Upload Report",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
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
      bottomNavigationBar: const AppFooter(),
    );
  }
}
