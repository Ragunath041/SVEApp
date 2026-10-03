import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supervisorapp/Services/ExamDetailsService.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:supervisorapp/pages/answer_sheet_capture.dart';
import 'package:supervisorapp/Services/StorageService.dart';
import 'package:supervisorapp/Services/logging/answer_upload_log_service.dart';
import 'package:supervisorapp/Services/CourseNameService.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supervisorapp/Services/attendance/student_attendance_service.dart';
import 'package:supervisorapp/Services/exam/exam_progress_service.dart';
import 'package:supervisorapp/pages/ImageCropperPage.dart';
import 'package:camera/camera.dart';

class UploadPage extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String centreName;
  final String courseCode;
  final String session;
  final String examDate;
  final String? attendanceId;
  final String? examType; // Add exam type parameter

  const UploadPage({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.centreName,
    required this.courseCode,
    required this.session,
    required this.examDate,
    this.attendanceId,
    this.examType, // Add exam type parameter
  });

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollbarKey = GlobalKey();

  List<String> _questionSlots = [];
  bool _isLoadingSlots = true;
  String? _selectedSlot; // Track the currently selected question slot

  // Track captured images for each slot
  // Key: Slot name (e.g. "Q1"), Value: List of image paths
  Map<String, List<String>> _capturedImagesPerSlot = {};
  // Track uploaded status per slot
  Map<String, bool> _uploadedSlots = {};

  @override
  void initState() {
    super.initState();
    _fetchSlots();
    _loadSavedImages();
  }

  // Load saved images from SharedPreferences
  Future<void> _loadSavedImages() async {
    final prefs = SharedPreferencesAsync();
    final key = 'captured_images_${widget.studentId}_${widget.courseCode}';
    final savedData = await prefs.getString(key);

    if (savedData != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(savedData);
        final Map<String, List<String>> loadedMap = {};

        decoded.forEach((slotKey, listValue) {
          final list = List<String>.from(listValue);
          if (list.isNotEmpty) {
            loadedMap[slotKey] = list;
          }
        });

        setState(() {
          _capturedImagesPerSlot = loadedMap;
        });
        print(' Loaded saved images: $_capturedImagesPerSlot');
      } catch (e) {
        print('Error loading saved images: $e');
      }
    }
  }

  // Save captured images to SharedPreferences
  Future<void> _saveCapturedImages() async {
    final prefs = SharedPreferencesAsync();
    final key = 'captured_images_${widget.studentId}_${widget.courseCode}';
    final encoded = json.encode(_capturedImagesPerSlot);
    await prefs.setString(key, encoded);
    print(' Saved images to SharedPreferences');
  }

  void _deleteImage(String slot, int index) {
    setState(() {
      final imagePath = _capturedImagesPerSlot[slot]![index];
      try {
        final file = File(imagePath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        print("Error deleting image file: $e");
      }
      _capturedImagesPerSlot[slot]!.removeAt(index);
      if (_capturedImagesPerSlot[slot]!.isEmpty) {
        _capturedImagesPerSlot.remove(slot);
      }
    });
    _saveCapturedImages();
  }

  Future<void> _fetchSlots() async {
    setState(() => _isLoadingSlots = true);

    final rawSlots = await ExamDetailsService.getQuestionSlots(
      fullCourseCode: widget.courseCode,
      date: widget.examDate,
    );
    if (mounted) {
      List<String> allSlots = ['FrontPage'];
      for (int i = 0; i < rawSlots.length; i++) {
        final s = rawSlots[i];
        if (s.toLowerCase() != 'frontpage') {
          allSlots.add("Q${i + 1}");
        }
      }
      setState(() {
        _questionSlots = allSlots;
        _isLoadingSlots = false;
      });
    }
  }

  List<int> _findIssueImageIndices(String slot) {
    final images = _capturedImagesPerSlot[slot] ?? [];
    final List<int> issueIndices = [];
    for (int i = 0; i < images.length; i++) {
      final f = File(images[i]);
      if (!f.existsSync() || f.lengthSync() < 1024) {
        issueIndices.add(i);
      }
    }
    return issueIndices;
  }

  Future<void> _startGuidedRecapture(
    String slot,
    List<int> issueIndices,
  ) async {
    if (issueIndices.isEmpty) return;

    List<String> currentImages = List<String>.from(
      _capturedImagesPerSlot[slot] ?? [],
    );

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      int successCount = 0;

      for (int step = 0; step < issueIndices.length; step++) {
        final targetIndex = issueIndices[step];
        if (targetIndex < 0 || targetIndex >= currentImages.length) continue;

        final pageNum = targetIndex + 1;
        final stepNum = step + 1;
        final totalSteps = issueIndices.length;

        if (!mounted) return;

        // Open camera for this specific page with indicator HUD
        final capturedPath = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (context) => AnswerSheetCameraScreen(
              camera: cameras.first,
              title: "Re-capturing Page $pageNum of ${currentImages.length}",
              subtitle: "Issue $stepNum of $totalSteps for $slot",
            ),
          ),
        );

        if (capturedPath == null || capturedPath.isEmpty) {
          // If user cancelled, break out but preserve progress
          break;
        }

        if (!mounted) return;

        // Crop the captured replacement photo with page indicator
        final croppedResult = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageCropperPage(
              image: XFile(capturedPath),
              title: "Crop Page $pageNum",
              subtitle: "Page $pageNum for $slot (Step $stepNum of $totalSteps)",
            ),
          ),
        );

        String finalPath = capturedPath;
        if (croppedResult != null && croppedResult is XFile) {
          try {
            final rawF = File(capturedPath);
            if (rawF.existsSync()) rawF.deleteSync();
          } catch (_) {}
          finalPath = croppedResult.path;
        }

        // Delete the old corrupted/replaced file from disk
        final oldPath = currentImages[targetIndex];
        try {
          final oldF = File(oldPath);
          if (oldF.existsSync()) {
            oldF.deleteSync();
          }
        } catch (e) {
          debugPrint("Error deleting old replaced file: $e");
        }

        // Replace at the exact target index
        currentImages[targetIndex] = finalPath;
        successCount++;

        // Save immediately
        setState(() {
          _capturedImagesPerSlot[slot] = List<String>.from(currentImages);
        });
        await _saveCapturedImages();
      }

      if (mounted && successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    successCount == 1
                        ? 'Page ${issueIndices.first + 1} recaptured successfully!'
                        : '$successCount pages recaptured and placed in order!',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error in guided recapture: $e");
    }
  }

  void _showMultiIssueDialog({
    required String slot,
    required List<int> issueIndices,
    String? customError,
  }) {
    final pageNumbersText = issueIndices.map((i) => "Page ${i + 1}").join(", ");
    final totalIssues = issueIndices.length;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: Colors.amber.shade800,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                totalIssues == 1
                    ? "Page Issue Detected"
                    : "Multiple Issues Detected",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              totalIssues == 1
                  ? "Found an issue with $pageNumbersText for $slot (missing or in Bytes)."
                  : "Found issues in $totalIssues pages for $slot:\n$pageNumbersText (missing or in Bytes).",
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              totalIssues == 1
                  ? "Would you like to re-capture $pageNumbersText to replace it in position ${issueIndices.first + 1}?"
                  : "Please re-capture these $totalIssues pages one by one to place them in their correct positions.",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(
              "Cancel",
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF444CE7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _startGuidedRecapture(slot, issueIndices);
            },
            icon: const Icon(Icons.camera_alt, size: 18),
            label: Text(
              totalIssues == 1
                  ? "Re-capture $pageNumbersText"
                  : "Re-capture ($totalIssues Pages)",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // Show images in a dialog
  void _showImagesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Captured Images for $_selectedSlot',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),

                // Images Grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: _capturedImagesPerSlot[_selectedSlot!]!.length,
                    itemBuilder: (context, index) {
                      final imagePath =
                          _capturedImagesPerSlot[_selectedSlot!]![index];
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: () =>
                                  _showFullScreenImage(context, imagePath),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(imagePath),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.65),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "Page ${index + 1}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () {
                                _deleteImage(_selectedSlot!, index);
                                Navigator.of(dialogContext).pop();
                                if (_capturedImagesPerSlot[_selectedSlot!] !=
                                    null) {
                                  _showImagesDialog();
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
                                  Icons.delete,
                                  size: 16,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            left: 6,
                            child: GestureDetector(
                              onTap: () async {
                                final croppedResult = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ImageCropperPage(
                                      image: XFile(imagePath),
                                    ),
                                  ),
                                );

                                if (croppedResult != null &&
                                    croppedResult is XFile) {
                                  try {
                                    final oldF = File(imagePath);
                                    if (oldF.existsSync()) oldF.deleteSync();
                                  } catch (_) {}
                                  setState(() {
                                    _capturedImagesPerSlot[_selectedSlot!]![index] =
                                        croppedResult.path;
                                  });
                                  _saveCapturedImages();
                                  if (dialogContext.mounted) {
                                    Navigator.of(
                                      dialogContext,
                                    ).pop(); // Briefly close to refresh
                                    _showImagesDialog(); // Re-open to show updated image
                                  }
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
                                  size: 16,
                                  color: Color(0xFF444CE7),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            left: 42,
                            child: GestureDetector(
                              onTap: () =>
                                  _showFullScreenImage(context, imagePath),
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
                                  size: 16,
                                  color: Color(0xFF444CE7),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // Add More Button (hidden for Front Page)
                if (!(_selectedSlot
                        ?.toLowerCase()
                        .replaceAll(' ', '')
                        .contains('front') ??
                    false)) ...[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(dialogContext).pop(); // Close dialog

                          final existingImages =
                              _capturedImagesPerSlot[_selectedSlot!];
                          final bool isFrontPage =
                              _selectedSlot
                                  ?.toLowerCase()
                                  .replaceAll(' ', '')
                                  .contains('front') ??
                              false;
                          print(
                            ' Add More: Existing images count: ${existingImages?.length ?? 0}',
                          );
                          print(' Add More: Existing images: $existingImages');

                          // Open camera with existing images
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AnswerSheetCaptureFlow(
                                studentId: widget.studentId,
                                studentName: widget.studentName,
                                centreName: widget.centreName,
                                courseCode: widget.courseCode,
                                existingImages:
                                    _capturedImagesPerSlot[_selectedSlot!],
                                singlePageOnly: isFrontPage,
                                slotName: _selectedSlot,
                              ),
                            ),
                          );

                          print(' Add More: Returned result: $result');
                          print(
                            ' Add More: Result length: ${result is List ? result.length : 'not a list'}',
                          );

                          if (result != null && result is List) {
                            setState(() {
                              _capturedImagesPerSlot[_selectedSlot!] =
                                  List<String>.from(result);
                            });
                            _saveCapturedImages();
                          }
                        },
                        icon: Icon(Icons.add_a_photo, size: 18),
                        label: Text(
                          'Add More',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canLeave = await _handleBackNavigation();
        if (canLeave && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final canLeave = await _handleBackNavigation();
              if (canLeave && context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/images/company_logo.png',
                  width: 35,
                  height: 35,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Student Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        body: SingleChildScrollView(
          child: Container(
            padding: EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Student Name",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.studentName,
                      style: TextStyle(fontSize: 14),
                    ),
                  ),

                  SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Student ID",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.studentId,
                      style: TextStyle(fontSize: 14),
                    ),
                  ),

                  SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Centre Name",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.centreName,
                      style: TextStyle(fontSize: 14),
                    ),
                  ),

                  SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Course Code",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(() {
                      final code = widget.courseCode;
                      final zIndex = code.indexOf(RegExp(r'[Zz]'));
                      if (zIndex > 0 &&
                          zIndex < code.length &&
                          code[zIndex - 1] != ' ') {
                        return '${code.substring(0, zIndex)} ${code.substring(zIndex)}';
                      }
                      return code;
                    }(), style: TextStyle(fontSize: 14)),
                  ),

                  SizedBox(height: 16),
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      "Upload Answer Sheets",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  SizedBox(height: 8),

                  // Progress indicator
                  if (_questionSlots.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Color.fromARGB(
                          255,
                          68,
                          76,
                          231,
                        ).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Color.fromARGB(
                            255,
                            68,
                            76,
                            231,
                          ).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.upload_file,
                            size: 18,
                            color: Color.fromARGB(255, 68, 76, 231),
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Progress: ${_uploadedSlots.values.where((v) => v == true).length}/${_questionSlots.length} uploaded",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color.fromARGB(255, 68, 76, 231),
                            ),
                          ),
                        ],
                      ),
                    ),

                  SizedBox(height: 12),

                  // Horizontally scrollable question buttons
                  SizedBox(
                    height: 60,
                    child: _isLoadingSlots
                        ? Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _questionSlots.isEmpty
                        ? Center(
                            child: Text(
                              "No question slots found.",
                              style: TextStyle(color: Colors.red),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            itemCount: _questionSlots.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: _buildQuestionButton(
                                  context,
                                  _questionSlots[index],
                                ),
                              );
                            },
                          ),
                  ),

                  SizedBox(height: 16),

                  // Scrollbar with arrow buttons
                  Row(
                    children: [
                      // Left Arrow
                      IconButton(
                        onPressed: () {
                          if (_scrollController.hasClients) {
                            _scrollController.animateTo(
                              _scrollController.offset - 150,
                              duration: Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                        icon: Icon(
                          Icons.arrow_back_ios,
                          size: 18,
                          color: Colors.grey.shade600,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),

                      SizedBox(width: 1),

                      // Scrollbar Track
                      Expanded(
                        child: GestureDetector(
                          onHorizontalDragUpdate: (details) {
                            if (_scrollController.hasClients &&
                                _scrollbarKey.currentContext != null) {
                              // Get the width of the track using the GlobalKey
                              RenderBox? box =
                                  _scrollbarKey.currentContext!
                                          .findRenderObject()
                                      as RenderBox?;
                              if (box != null) {
                                double trackWidth = box.size.width;

                                // Calculate the new scroll position based on drag
                                double maxScroll =
                                    _scrollController.position.maxScrollExtent;
                                double dragPosition = details.localPosition.dx;
                                double progress = (dragPosition / trackWidth)
                                    .clamp(0.0, 1.0);
                                double newScrollOffset = maxScroll * progress;

                                _scrollController.jumpTo(
                                  newScrollOffset.clamp(0.0, maxScroll),
                                );
                              }
                            }
                          },
                          onTapDown: (details) {
                            if (_scrollController.hasClients &&
                                _scrollbarKey.currentContext != null) {
                              // Get the width of the track using the GlobalKey
                              RenderBox? box =
                                  _scrollbarKey.currentContext!
                                          .findRenderObject()
                                      as RenderBox?;
                              if (box != null) {
                                double trackWidth = box.size.width;

                                // Calculate the new scroll position based on tap
                                double maxScroll =
                                    _scrollController.position.maxScrollExtent;
                                double tapPosition = details.localPosition.dx;
                                double progress = (tapPosition / trackWidth)
                                    .clamp(0.0, 1.0);
                                double newScrollOffset = maxScroll * progress;

                                _scrollController.animateTo(
                                  newScrollOffset.clamp(0.0, maxScroll),
                                  duration: Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                );
                              }
                            }
                          },
                          child: Container(
                            key: _scrollbarKey,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return AnimatedBuilder(
                                  animation: _scrollController,
                                  builder: (context, child) {
                                    // Calculate scroll progress with safety checks
                                    double maxScroll = 0;
                                    double currentScroll = 0;

                                    if (_scrollController.hasClients &&
                                        _scrollController
                                            .position
                                            .hasContentDimensions) {
                                      maxScroll = _scrollController
                                          .position
                                          .maxScrollExtent;
                                      currentScroll = _scrollController.offset;
                                    }

                                    double progress = maxScroll > 0
                                        ? (currentScroll / maxScroll).clamp(
                                            0.0,
                                            1.0,
                                          )
                                        : 0;

                                    // Calculate thumb width (proportional to visible content)
                                    double thumbWidth =
                                        constraints.maxWidth * 0.3;
                                    double thumbPosition =
                                        ((constraints.maxWidth - thumbWidth) *
                                                progress)
                                            .clamp(
                                              0.0,
                                              constraints.maxWidth - thumbWidth,
                                            );

                                    return Stack(
                                      children: [
                                        Positioned(
                                          left: thumbPosition,
                                          child: Container(
                                            width: thumbWidth,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: const Color.fromARGB(
                                                255,
                                                65,
                                                65,
                                                65,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      SizedBox(width: 8),

                      // Right Arrow
                      IconButton(
                        onPressed: () {
                          if (_scrollController.hasClients) {
                            _scrollController.animateTo(
                              _scrollController.offset + 150,
                              duration: Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                        icon: Icon(
                          Icons.arrow_forward_ios,
                          size: 18,
                          color: Colors.grey.shade600,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                    ],
                  ),

                  // SizedBox(height: 60),

                  // Capture Photograph / Add More Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _selectedSlot == null
                          ? null
                          : () async {
                              final hasImages =
                                  _capturedImagesPerSlot[_selectedSlot!]
                                      ?.isNotEmpty ??
                                  false;

                              if (hasImages) {
                                // Show images in a dialog
                                _showImagesDialog();
                              } else {
                                // If no images, open camera capture flow
                                print(
                                  ' Opening camera for slot: $_selectedSlot',
                                );

                                final bool isFrontPage =
                                    _selectedSlot
                                        ?.toLowerCase()
                                        .replaceAll(' ', '')
                                        .contains('front') ??
                                    false;

                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AnswerSheetCaptureFlow(
                                          studentId: widget.studentId,
                                          studentName: widget.studentName,
                                          centreName: widget.centreName,
                                          courseCode: widget.courseCode,
                                          existingImages: [],
                                          singlePageOnly: isFrontPage,
                                          slotName: _selectedSlot,
                                        ),
                                  ),
                                );

                                print(' Camera returned with result: $result');
                                print(' Result type: ${result.runtimeType}');

                                if (result != null && result is List) {
                                  print(
                                    ' Saving ${result.length} images for slot $_selectedSlot',
                                  );
                                  setState(() {
                                    _capturedImagesPerSlot[_selectedSlot!] =
                                        List<String>.from(result);
                                    print(
                                      ' Images saved! Total slots with images: ${_capturedImagesPerSlot.length}',
                                    );
                                    print(
                                      ' Images for $_selectedSlot: ${_capturedImagesPerSlot[_selectedSlot!]?.length}',
                                    );
                                  });
                                  // Save to SharedPreferences
                                  _saveCapturedImages();
                                } else {
                                  print(
                                    ' No images returned or invalid result',
                                  );
                                }
                              }
                            },
                      icon: Icon(
                        (_selectedSlot != null &&
                                (_capturedImagesPerSlot[_selectedSlot!]
                                        ?.isNotEmpty ??
                                    false))
                            ? Icons.visibility
                            : Icons.camera_alt,
                        size: 18,
                      ),
                      label: Text(
                        _selectedSlot == null
                            ? "Capture Photograph"
                            : (_capturedImagesPerSlot[_selectedSlot!]
                                      ?.isNotEmpty ??
                                  false)
                            ? "View"
                            : "Capture Photograph $_selectedSlot",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            (_selectedSlot != null &&
                                (_capturedImagesPerSlot[_selectedSlot!]
                                        ?.isNotEmpty ??
                                    false))
                            ? Colors.green
                            : Color.fromARGB(255, 68, 76, 231),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        disabledForegroundColor: Colors.grey.shade500,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),

                  SizedBox(height: 12),

                  // Upload Answer Sheet Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          (_selectedSlot == null ||
                              !(_capturedImagesPerSlot[_selectedSlot!]
                                      ?.isNotEmpty ??
                                  false))
                          ? null
                          : () async {
                              final slotToUpload = _selectedSlot!;
                              final issueIndices = _findIssueImageIndices(
                                slotToUpload,
                              );
                              if (issueIndices.isNotEmpty) {
                                _showMultiIssueDialog(
                                  slot: slotToUpload,
                                  issueIndices: issueIndices,
                                );
                                return;
                              }

                              // Upload specific slot
                              // Show loading dialog
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (c) =>
                                    Center(child: CircularProgressIndicator()),
                              );

                              try {
                                final storageService = StorageService();
                                final result = await storageService
                                    .uploadAnswerSheets(
                                      studentId: widget.studentId,
                                      studentName: widget.studentName,
                                      courseCode: widget.courseCode,
                                      capturedImages: {
                                        _selectedSlot!:
                                            _capturedImagesPerSlot[_selectedSlot!]!,
                                      },
                                    );
                                storageService.dispose();

                                if (result['success'] == true) {
                                  // Log the upload to S3 CSV
                                  try {
                                    final prefs = SharedPreferencesAsync();
                                    final supervisorId =
                                        await prefs.getString(
                                          'current_supervisor_id',
                                        ) ??
                                        'unknown';

                                    // Normalize course code (e.g. DUMM ZA111-EC3R -> DUMMZA111)
                                    final shortCourseCode = widget.courseCode
                                        .split('-')
                                        .first
                                        .replaceAll(' ', '');

                                    // Fetch actual course name from Lambda
                                    String courseName = widget
                                        .courseCode; // Default to full code
                                    try {
                                      print(
                                        ' Fetching course name for: $shortCourseCode',
                                      );
                                      final courseNameResult =
                                          await CourseNameService.getCourseName(
                                            shortCourseCode,
                                          );
                                      if (courseNameResult['success'] == true) {
                                        courseName =
                                            courseNameResult['courseName'] ??
                                            widget.courseCode;
                                        print(' Got course name: $courseName');
                                      } else {
                                        print(
                                          ' Could not fetch course name, using course code',
                                        );
                                      }
                                    } catch (courseNameError) {
                                      print(
                                        ' Error fetching course name: $courseNameError',
                                      );
                                      // Continue with default course name
                                    }

                                    await UploadLogService.logUpload(
                                      supervisorId: supervisorId,
                                      studentId: widget.studentId,
                                      courseCode:
                                          shortCourseCode, // Short code: DUMMZA110
                                      courseName:
                                          courseName, // Actual course name from database
                                      questionNo:
                                          _selectedSlot!, // Q1, Q2, Q3, etc.
                                    );
                                    print(' Upload logged successfully');
                                  } catch (logError) {
                                    print(' Failed to log upload: $logError');
                                    // Don't fail the upload if logging fails
                                  }

                                  // Update DynamoDB Attendance & Finished Tables
                                  if (widget.attendanceId != null) {
                                    try {
                                      final uploadedQ =
                                          _selectedSlot!; // e.g., "FrontPage" or "Q1"
                                      final isFrontPage = uploadedQ
                                          .toLowerCase()
                                          .contains('front');
                                      final qNum = isFrontPage
                                          ? 0
                                          : (int.tryParse(
                                                  uploadedQ.replaceAll(
                                                    RegExp(r'[^0-9]'),
                                                    '',
                                                  ),
                                                ) ??
                                                0);

                                      // 1. Decrement pending count
                                      await DynamoDBAttendanceService.decrementNoOfQuestionsPending(
                                        bitsId: widget.studentId,
                                        attendanceId: widget.attendanceId!,
                                      );

                                      // 2. Ensure initial finishedTable record exists (will skip if it already does)
                                      await DynamoDBFinishedService.createInitialRecord(
                                        bitsId: widget.studentId,
                                        attendanceId: widget.attendanceId!,
                                        courseCode: widget.courseCode
                                            .toUpperCase()
                                            .replaceAll(' ', ''),
                                        examDate: widget.examDate,
                                        sessionType: widget.session,
                                      );

                                      // 3. Update finishedTable with page count
                                      await DynamoDBFinishedService.updateQuestionTimestamp(
                                        bitsId: widget.studentId,
                                        attendanceId: widget.attendanceId!,
                                        questionNumber: qNum,
                                        uploadTime: DateTime.now(),
                                        pageCount:
                                            _capturedImagesPerSlot[uploadedQ]
                                                ?.length ??
                                            0,
                                      );

                                      print(
                                        ' DynamoDB records updated for $uploadedQ',
                                      );
                                    } catch (dbError) {
                                      print(
                                        ' Failed to update DynamoDB: $dbError',
                                      );
                                      // Soft fail
                                    }
                                  }

                                  String uploadedSlot =
                                      _selectedSlot!; // Store before changing

                                  // Clean up uploaded images
                                  try {
                                    // 1. Delete image files from disk
                                    final imagesToDelete =
                                        _capturedImagesPerSlot[uploadedSlot];
                                    if (imagesToDelete != null) {
                                      for (var imagePath in imagesToDelete) {
                                        final file = File(imagePath);
                                        if (await file.exists()) {
                                          await file.delete();
                                          print(
                                            ' Deleted image file: $imagePath',
                                          );
                                        }
                                      }
                                    }

                                    // 2. Remove from memory
                                    _capturedImagesPerSlot.remove(uploadedSlot);

                                    // 3. Update SharedPreferences
                                    await _saveCapturedImages();
                                    print(
                                      ' Cleaned up images for $uploadedSlot',
                                    );
                                  } catch (cleanupError) {
                                    print(
                                      ' Error cleaning up images: $cleanupError',
                                    );
                                    // Don't fail the upload if cleanup fails
                                  }

                                  setState(() {
                                    _uploadedSlots[_selectedSlot!] = true;

                                    // Auto-select next unuploaded slot
                                    String? nextSlot;
                                    for (
                                      int i = 0;
                                      i < _questionSlots.length;
                                      i++
                                    ) {
                                      String slotName = _questionSlots[i];
                                      if (_uploadedSlots[slotName] != true) {
                                        nextSlot = slotName;
                                        break;
                                      }
                                    }

                                    if (nextSlot != null) {
                                      _selectedSlot = nextSlot;
                                      // Scroll to the next slot
                                      if (_scrollController.hasClients) {
                                        int nextIndex = _questionSlots.indexOf(
                                          nextSlot,
                                        );
                                        double scrollPosition =
                                            nextIndex *
                                            72.0; // 60 width + 12 padding
                                        _scrollController.animateTo(
                                          scrollPosition,
                                          duration: const Duration(
                                            milliseconds: 500,
                                          ),
                                          curve: Curves.easeInOut,
                                        );
                                      }
                                    } else {
                                      _selectedSlot = null; // All uploaded
                                    }
                                  });

                                  int uploadedCount = _uploadedSlots.values
                                      .where((v) => v == true)
                                      .length;
                                  bool isAllUploaded =
                                      _questionSlots.isNotEmpty &&
                                      uploadedCount == _questionSlots.length;

                                  // Close loading dialog on success
                                  if (mounted) {
                                    Navigator.of(this.context).pop();
                                  }

                                  if (isAllUploaded) {
                                    // 1. Auto-update Finished Time in DynamoDB
                                    if (widget.attendanceId != null) {
                                      try {
                                        await DynamoDBAttendanceService.updateFinishedTime(
                                          bitsId: widget.studentId,
                                          attendanceId: widget.attendanceId!,
                                          finishedTime: DateTime.now(),
                                        );
                                        print(
                                          ' Exam marked as finished automatically in DynamoDB',
                                        );
                                      } catch (dbError) {
                                        print(
                                          ' Failed to auto-update finishedTime: $dbError',
                                        );
                                      }
                                    }

                                    // 2. Show completion dialog and return to student list
                                    if (mounted) {
                                      await showDialog(
                                        context: this.context,
                                        barrierDismissible: false,
                                        builder: (dialogCtx) => AlertDialog(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          title: Row(
                                            children: const [
                                              Icon(
                                                Icons.check_circle,
                                                color: Colors.green,
                                                size: 28,
                                              ),
                                              SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  "All Sheets Uploaded",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 18,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          content: Text(
                                            "All $uploadedCount answer sheets have been uploaded successfully. The student's exam session is now marked as complete.",
                                            style: const TextStyle(
                                              fontSize: 14,
                                            ),
                                          ),
                                          actions: [
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    const Color.fromARGB(
                                                      255,
                                                      68,
                                                      76,
                                                      231,
                                                    ),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 24,
                                                      vertical: 10,
                                                    ),
                                              ),
                                              onPressed: () {
                                                Navigator.of(dialogCtx).pop();
                                                if (mounted) {
                                                  Navigator.of(
                                                    this.context,
                                                  ).pop();
                                                }
                                              },
                                              child: const Text(
                                                "OK",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  } else {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "$uploadedSlot uploaded successfully ($uploadedCount/${_questionSlots.length} completed)",
                                          ),
                                          backgroundColor: Colors.green,
                                          duration: const Duration(seconds: 2),
                                          behavior: SnackBarBehavior.floating,
                                          margin: const EdgeInsets.all(16),
                                        ),
                                      );
                                    }
                                  }
                                } else {
                                  // Close loading dialog on failure
                                  if (mounted) {
                                    Navigator.of(this.context).pop();
                                    final errorMsg =
                                        result['error']?.toString() ??
                                        'Please check your connection and try again.';

                                    // If image issue, show popup dialog with Re-capture button
                                    if (errorMsg.toLowerCase().contains(
                                          'missing',
                                        ) ||
                                        errorMsg.toLowerCase().contains(
                                          '0-byte',
                                        ) ||
                                        errorMsg.toLowerCase().contains(
                                          'recapture',
                                        ) ||
                                        errorMsg.toLowerCase().contains(
                                          'corrupt',
                                        ) ||
                                        errorMsg.toLowerCase().contains(
                                          'image',
                                        ) ||
                                        errorMsg.toLowerCase().contains(
                                          'page',
                                        )) {
                                      final issueIndices =
                                          _findIssueImageIndices(
                                            _selectedSlot ?? '',
                                          );
                                      _showMultiIssueDialog(
                                        slot: _selectedSlot ?? 'this question',
                                        issueIndices: issueIndices.isNotEmpty
                                            ? issueIndices
                                            : [0],
                                        customError: errorMsg,
                                      );
                                    } else {
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "Upload failed: $errorMsg",
                                          ),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                          margin: const EdgeInsets.all(16),
                                        ),
                                      );
                                    }
                                  }
                                }
                              } catch (e) {
                                // Close loading dialog if still open
                                if (mounted) {
                                  Navigator.of(this.context).pop();
                                  final errorMsg = e.toString().replaceFirst(
                                    RegExp(r'^Exception:\s*'),
                                    '',
                                  );

                                  if (errorMsg.toLowerCase().contains(
                                        'missing',
                                      ) ||
                                      errorMsg.toLowerCase().contains(
                                        '0-byte',
                                      ) ||
                                      errorMsg.toLowerCase().contains(
                                        'recapture',
                                      ) ||
                                      errorMsg.toLowerCase().contains(
                                        'corrupt',
                                      ) ||
                                      errorMsg.toLowerCase().contains(
                                        'image',
                                      ) ||
                                      errorMsg.toLowerCase().contains('page')) {
                                    final issueIndices = _findIssueImageIndices(
                                      _selectedSlot ?? '',
                                    );
                                    _showMultiIssueDialog(
                                      slot: _selectedSlot ?? 'this question',
                                      issueIndices: issueIndices.isNotEmpty
                                          ? issueIndices
                                          : [0],
                                      customError: errorMsg,
                                    );
                                  } else {
                                    ScaffoldMessenger.of(
                                      this.context,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "Upload failed: $errorMsg",
                                        ),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                        margin: const EdgeInsets.all(16),
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                      icon: Icon(Icons.upload_file, size: 18),
                      label: Text(
                        _selectedSlot == null
                            ? "Upload Answer Sheet"
                            : "Upload Answer Sheet $_selectedSlot",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color.fromARGB(255, 68, 76, 231),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        disabledForegroundColor: Colors.grey.shade500,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        bottomNavigationBar: const AppFooter(),
      ),
    );
  }

  Future<bool> _handleBackNavigation() async {
    if (!mounted) return true;

    // 1. If there are captured unuploaded images, warn user
    if (_capturedImagesPerSlot.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text("Discard Captured Images?"),
          content: const Text(
            "You have captured answer sheet images that are not yet uploaded. Leaving now will discard these unuploaded images.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text("Stay"),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text("Discard & Exit"),
            ),
          ],
        ),
      );
      if (discard != true) return false;
    }

    if (!mounted) return true;

    // 2. If some (but not all) questions were uploaded, prompt to finalize
    final uploadedList =
        _uploadedSlots.entries
            .where((e) => e.value == true)
            .map((e) => e.key)
            .toList()
          ..sort();

    if (uploadedList.isNotEmpty &&
        uploadedList.length < _questionSlots.length) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text("Finish Student Exam?"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "You have uploaded ${uploadedList.length} of ${_questionSlots.length} questions (${uploadedList.join(', ')}).",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Do you want to finalize this exam session and mark it complete for this student?",
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.pop(c, true),
              child: const Text("Yes, Finish Exam"),
            ),
          ],
        ),
      );

      if (confirm == true) {
        if (widget.attendanceId != null) {
          try {
            await DynamoDBAttendanceService.updateFinishedTime(
              bitsId: widget.studentId,
              attendanceId: widget.attendanceId!,
              finishedTime: DateTime.now(),
            );
            print(' Exam marked as finished on back in DynamoDB');
          } catch (e) {
            print(' Error marking finished on back: $e');
          }
        }
        return true;
      }
      return false;
    }

    return true;
  }

  // Build individual question button
  Widget _buildQuestionButton(BuildContext context, String slotName) {
    bool isSelected = _selectedSlot == slotName;
    bool isUploaded = _uploadedSlots[slotName] == true;
    bool isFrontPage = slotName.toLowerCase().contains('front');
    String displayLabel = isFrontPage ? "Front\nPage" : slotName;
    double buttonWidth = isFrontPage ? 75 : 60;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedSlot = isSelected ? null : slotName;
        });
      },
      child: Container(
        width: buttonWidth,
        height: 60,
        decoration: BoxDecoration(
          color: isUploaded
              ? Colors.green
              : (isSelected
                    ? const Color.fromARGB(255, 68, 76, 231)
                    : const Color.fromARGB(255, 68, 76, 231).withOpacity(0.2)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUploaded
                ? Colors.green.shade800
                : (isSelected
                      ? const Color.fromARGB(255, 68, 76, 231)
                      : Colors.white),
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  const BoxShadow(
                    color: Color.fromARGB(255, 255, 255, 255),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isUploaded)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.check_circle, color: Colors.white, size: 16),
              ),
            Center(
              child: Text(
                displayLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isFrontPage ? 13 : 16,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                  color: (isSelected || isUploaded)
                      ? Colors.white
                      : const Color.fromARGB(255, 68, 76, 231),
                ),
              ),
            ),
          ],
        ),
      ),
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
