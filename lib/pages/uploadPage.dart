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
import 'package:image_picker/image_picker.dart';

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
  bool _showImagesPreview =
      true; // Track whether to show captured images preview

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
        setState(() {
          _capturedImagesPerSlot = decoded.map(
            (key, value) => MapEntry(key, List<String>.from(value)),
          );
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

    final slots = await ExamDetailsService.getQuestionSlots(
      fullCourseCode: widget.courseCode,
      date: widget.examDate,
    );
    if (mounted) {
      setState(() {
        _questionSlots = slots;
        _isLoadingSlots = false;
      });
    }
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
                      Text(
                        'Captured Images for $_selectedSlot',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
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
                                  setState(() {
                                    _capturedImagesPerSlot[_selectedSlot!]![index] =
                                        croppedResult.path;
                                  });
                                  _saveCapturedImages();
                                  Navigator.of(
                                    dialogContext,
                                  ).pop(); // Briefly close to refresh
                                  _showImagesDialog(); // Re-open to show updated image
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

                // Add More Button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.of(dialogContext).pop(); // Close dialog

                        final existingImages =
                            _capturedImagesPerSlot[_selectedSlot!];
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
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
            SizedBox(width: 12),
            Expanded(
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
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.studentId, style: TextStyle(fontSize: 14)),
                ),

                SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Centre Name",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),

                SizedBox(height: 8),

                // Progress indicator
                if (_questionSlots.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Color.fromARGB(255, 68, 76, 231).withOpacity(0.1),
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
                              padding: EdgeInsets.only(right: 12),
                              child: _buildQuestionButton(
                                context,
                                "Q${index + 1}", // Show Q1, Q2, etc. instead of filename
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
                                _scrollbarKey.currentContext!.findRenderObject()
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
                                _scrollbarKey.currentContext!.findRenderObject()
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
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
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
                              print(' Opening camera for slot: $_selectedSlot');

                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AnswerSheetCaptureFlow(
                                    studentId: widget.studentId,
                                    studentName: widget.studentName,
                                    centreName: widget.centreName,
                                    courseCode: widget.courseCode,
                                    existingImages: [],
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
                                print(' No images returned or invalid result');
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
                                  String courseName =
                                      widget.courseCode; // Default to full code
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
                                        _selectedSlot!; // e.g., "Q1"
                                    final qNum =
                                        int.tryParse(
                                          uploadedQ.replaceAll(
                                            RegExp(r'[^0-9]'),
                                            '',
                                          ),
                                        ) ??
                                        0;

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
                                  print(' Cleaned up images for $uploadedSlot');
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
                                    String slotName = "Q${i + 1}";
                                    if (_uploadedSlots[slotName] != true) {
                                      nextSlot = slotName;
                                      break;
                                    }
                                  }

                                  if (nextSlot != null) {
                                    _selectedSlot = nextSlot;
                                    // Scroll to the next slot
                                    if (_scrollController.hasClients) {
                                      int nextIndex =
                                          int.parse(nextSlot.substring(1)) - 1;
                                      double scrollPosition =
                                          nextIndex *
                                          72.0; // 60 width + 12 padding
                                      _scrollController.animateTo(
                                        scrollPosition,
                                        duration: Duration(milliseconds: 500),
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
                                // Close loading dialog on success
                                if (mounted) Navigator.pop(context);

                                ScaffoldMessenger.of(context).showSnackBar(
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
                              } else {
                                // Close loading dialog on failure
                                if (mounted) Navigator.pop(context);

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
                            } catch (e) {
                              // Close loading dialog if still open
                              if (mounted) Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Upload failed. Please check your connection and try again.",
                                  ),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                  margin: EdgeInsets.all(16),
                                ),
                              );
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
                      backgroundColor: Colors.blue,
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

                // Submit All Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        (_uploadedSlots.values.any((v) => v == true) &&
                            _capturedImagesPerSlot.isEmpty)
                        ? _finishExam
                        : null,
                    icon: Icon(Icons.check_circle, size: 18),
                    label: Text(
                      "Submit All",
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

                if (_showImagesPreview &&
                    _selectedSlot != null &&
                    (_capturedImagesPerSlot[_selectedSlot!]?.isNotEmpty ??
                        false)) ...[
                  SizedBox(height: 24),
                  Divider(),
                  SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Captured Images for $_selectedSlot",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
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
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () {
                                _deleteImage(_selectedSlot!, index);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
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
                          ),
                          Positioned(
                            bottom: 4,
                            left: 4,
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
                                  setState(() {
                                    _capturedImagesPerSlot[_selectedSlot!]![index] =
                                        croppedResult.path;
                                  });
                                  _saveCapturedImages();
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.crop,
                                  size: 14,
                                  color: Color(0xFF444CE7),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 4,
                            left: 32,
                            child: GestureDetector(
                              onTap: () =>
                                  _showFullScreenImage(context, imagePath),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
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
                          ),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        // Open capture flow with existing images
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
                            ),
                          ),
                        );

                        if (result != null && result is List) {
                          setState(() {
                            _capturedImagesPerSlot[_selectedSlot!] =
                                List<String>.from(result);
                          });
                          // Save to SharedPreferences
                          _saveCapturedImages();
                        }
                      },
                      icon: Icon(Icons.add_a_photo, size: 18),
                      label: Text(
                        "Add more",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),

      bottomNavigationBar: const AppFooter(),
    );
  }

  Future<void> _finishExam() async {
    // Build list of uploaded question slot names
    final uploadedList =
        _uploadedSlots.entries
            .where((e) => e.value == true)
            .map((e) => e.key)
            .toList()
          ..sort();

    final uploadedText = uploadedList.join(', ');

    // Confirm dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Finalize & Submit Exam'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have uploaded: ${uploadedText.isEmpty ? "None" : uploadedText}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'Are you sure you want to submit and mark this session as complete for this student?',
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Submit'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (widget.attendanceId != null) {
      try {
        final success = await DynamoDBAttendanceService.updateFinishedTime(
          bitsId: widget.studentId,
          attendanceId: widget.attendanceId!,
          finishedTime: DateTime.now(),
        );

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Exam finalized successfully."),
              backgroundColor: Colors.green,
            ),
          );
        }
        print(' Exam marked as finished in DynamoDB');
      } catch (e) {
        print(' Error marking finished: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Connection notice: Finish time could not be saved online.",
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } else {
      print(' Cannot mark finished: attendanceId is null');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Attendance record not found for this student."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }

    Navigator.pop(context); // Go back to student selection
  }

  // Build individual question button
  Widget _buildQuestionButton(BuildContext context, String slotName) {
    bool isSelected = _selectedSlot == slotName;
    bool isUploaded = _uploadedSlots[slotName] == true;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedSlot = isSelected ? null : slotName;
        });
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isUploaded
              ? Colors.green
              : (isSelected
                    ? Color.fromARGB(255, 68, 76, 231)
                    : Color.fromARGB(255, 68, 76, 231).withOpacity(0.2)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUploaded
                ? Colors.green.shade800
                : (isSelected
                      ? Color.fromARGB(255, 68, 76, 231)
                      : Colors.white),
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
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
              Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.check_circle, color: Colors.white, size: 16),
              ),
            Center(
              child: Text(
                slotName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: (isSelected || isUploaded)
                      ? Colors.white
                      : Color.fromARGB(255, 68, 76, 231),
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
