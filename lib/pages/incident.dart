import 'package:flutter/material.dart';
import 'package:supervisorapp/pages/camera_capture_page.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:supervisorapp/Services/ExamDetailsService.dart';
import 'package:supervisorapp/Services/CourseNameService.dart';

class IncidentReportPage extends StatefulWidget {
  final String centre;
  const IncidentReportPage({Key? key, required this.centre}) : super(key: key);

  @override
  State<IncidentReportPage> createState() => _IncidentReportPageState();
}

class _IncidentReportPageState extends State<IncidentReportPage> {
  final TextEditingController studentIdController = TextEditingController();
  final FocusNode studentIdFocusNode = FocusNode();
  final TextEditingController studentNameController = TextEditingController();
  final TextEditingController courseCodeController = TextEditingController();
  final TextEditingController courseNameController = TextEditingController();
  final TextEditingController cityNameController = TextEditingController();
  final TextEditingController centreNameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController anyOtherDetailsController =
      TextEditingController();

  String? selectedUFM;
  String? selectedOffence;

  // Student IDs dropdown
  List<String> _allStudentIds = [];
  List<String> _filteredStudentIds = [];
  bool _showDropdown = false;
  bool _isLoadingStudentIds = true;

  // Course codes dropdown
  List<String> _availableCourseCodes = [];
  List<String> _filteredCourseCodes = [];
  bool _showCourseDropdown = false;
  final FocusNode courseCodeFocusNode = FocusNode();

  // Loading states
  bool _isLoadingStudentDetails = false;
  bool _isLoadingCourseName = false;

  // Track session for each course code
  Map<String, String> _courseSessionMap = {};

  final List<String> offenceOptions = [
    'With a device - mobile phone / smart watch / earphones / earpods',
    'With paper chits',
    'With a mobile outside exam hall during exam time',
    'Writing during scan \u0026 upload time',
    'Navigating away from the exam browser',
    'Unruly behaviour at the exam centre',
    'Bio breaks taken (Regular / Medical Issue / Multiple - intentional)',
    'Talking to other student(s)',
    'Text written on desk / body / clothes / hall ticket',
    'Copying from other student(s)',
    'Exam taken by other person (impersonation)',
    'Browsing tolerance exceeded',
    'Use of abusive language',
    'Any other (give details below)',
  ];

  final List<String> ufmOptions = ['Possession', 'Usage'];

  @override
  void initState() {
    super.initState();
    studentIdController.addListener(_onStudentIdChanged);
    studentIdFocusNode.addListener(_onFocusChanged);
    courseCodeController.addListener(_onCourseCodeChanged);
    courseCodeFocusNode.addListener(_onCourseCodeFocusChanged);
    _loadStudentIds();
  }

  @override
  void dispose() {
    studentIdController.removeListener(_onStudentIdChanged);
    studentIdFocusNode.removeListener(_onFocusChanged);
    courseCodeController.removeListener(_onCourseCodeChanged);
    courseCodeFocusNode.removeListener(_onCourseCodeFocusChanged);
    studentIdController.dispose();
    studentIdFocusNode.dispose();
    courseCodeFocusNode.dispose();
    studentNameController.dispose();
    courseCodeController.dispose();
    courseNameController.dispose();
    cityNameController.dispose();
    centreNameController.dispose();
    descriptionController.dispose();
    anyOtherDetailsController.dispose();
    super.dispose();
  }

  Future<void> _loadStudentIds() async {
    try {
      print(' [IncidentPage] Loading students for center: ${widget.centre}');

      // 1. Get all exams for the center today (regardless of time)
      final activeExams = await ExamDetailsService.getCenterExamsForToday(
        widget.centre,
      );

      if (activeExams.isEmpty) {
        print(
          ' [IncidentPage] No active exams found for center: ${widget.centre}',
        );
        setState(() {
          _allStudentIds = [];
          _isLoadingStudentIds = false;
        });
        return;
      }

      // 2. Get student IDs for those active exams in this center
      final studentIds =
          await ExamDetailsService.getStudentIdsInCentreForActiveExam(
            widget.centre,
            activeExams,
          );

      setState(() {
        _allStudentIds = studentIds;
        _isLoadingStudentIds = false;
      });
      print(
        ' [IncidentPage] Loaded ${studentIds.length} student IDs for center: ${widget.centre}',
      );
    } catch (e) {
      setState(() {
        _isLoadingStudentIds = false;
      });
      print(' [IncidentPage] Error loading student IDs: $e');
    }
  }

  void _onStudentIdChanged() {
    final query = studentIdController.text.trim().toUpperCase();

    if (query.isEmpty) {
      setState(() {
        _filteredStudentIds = [];
        _showDropdown = false;
      });
    } else {
      setState(() {
        _filteredStudentIds = _allStudentIds
            .where((id) => id.toUpperCase().startsWith(query))
            .toList();
        _showDropdown = _filteredStudentIds.isNotEmpty;
      });
    }
  }

  void _onFocusChanged() {
    if (studentIdFocusNode.hasFocus) {
      final query = studentIdController.text.trim().toUpperCase();

      setState(() {
        if (query.isEmpty) {
          _filteredStudentIds = _allStudentIds;
          _showDropdown = _allStudentIds.isNotEmpty;
        } else {
          _filteredStudentIds = _allStudentIds
              .where((id) => id.toUpperCase().startsWith(query))
              .toList();
          _showDropdown = _filteredStudentIds.isNotEmpty;
        }
      });
    } else {
      Future.delayed(Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() {
            _showDropdown = false;
          });
        }
      });
    }
  }

  void _onCourseCodeChanged() {
    final query = courseCodeController.text.trim().toUpperCase();

    if (query.isEmpty) {
      setState(() {
        _filteredCourseCodes = [];
        _showCourseDropdown = false;
      });
    } else {
      setState(() {
        _filteredCourseCodes = _availableCourseCodes
            .where((code) => code.toUpperCase().contains(query))
            .toList();
        _showCourseDropdown = _filteredCourseCodes.isNotEmpty;
      });
    }
  }

  void _onCourseCodeFocusChanged() {
    if (courseCodeFocusNode.hasFocus) {
      final query = courseCodeController.text.trim().toUpperCase();

      setState(() {
        // ALWAYS show all available course codes when focused,
        // so user can change from current selection.
        _filteredCourseCodes = _availableCourseCodes;
        _showCourseDropdown = _availableCourseCodes.isNotEmpty;
      });
    } else {
      Future.delayed(Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() {
            _showCourseDropdown = false;
          });
        }
      });
    }
  }

  Future<void> _fetchStudentDetails(String studentId) async {
    print(
      ' \n[IncidentPage] >>> STEP: Fetching details for student: "$studentId"',
    );
    // Show loading overlay
    setState(() {
      _isLoadingStudentDetails = true;
    });

    try {
      final result = await ExamDetailsService.getStudentExamDetails(studentId);
      print(' [IncidentPage] Raw Result from ExamDetailsService: $result');

      // Hide loading
      if (mounted) {
        setState(() {
          _isLoadingStudentDetails = false;
        });
      }

      if (result['success'] == true) {
        // Extract course codes from exams
        final rawExams = result['exams'];
        print(' [IncidentPage] Raw Exams Data: $rawExams');

        final List<Map<String, String>> exams = List<Map<String, String>>.from(
          rawExams ?? [],
        );

        final courseCodes = exams
            .map((exam) => exam['fullCourseCode'] ?? '')
            .where((code) => code.isNotEmpty)
            .toList();

        print(' [IncidentPage] Extracted Course Codes: $courseCodes');

        // Extract city name from centre field
        String cityName = '';
        String centreName = '';
        final centre = result['centre']?.toString() ?? '';
        print(' [IncidentPage] Parsing Centre string: "$centre"');

        if (centre.isNotEmpty) {
          if (centre.contains('-')) {
            final parts = centre.split('-');
            cityName = parts[0].trim();
            centreName = parts.length > 1 ? parts[1].trim() : '';
          } else if (centre.contains(',')) {
            final parts = centre.split(',');
            cityName = parts[0].trim();
            centreName = parts.length > 1 ? parts[1].trim() : '';
          } else {
            cityName = centre.trim();
          }
        }

        print(
          ' [IncidentPage] Parsed Location -> City: "$cityName", Centre: "$centreName"',
        );

        setState(() {
          studentNameController.text = result['studentName']?.toString() ?? '';
          cityNameController.text = cityName;
          centreNameController.text = centreName;
          _availableCourseCodes = courseCodes;
          _filteredCourseCodes = courseCodes;

          courseCodeController.text = '';
          courseNameController.text = '';
        });

        print(' [IncidentPage] UI State updated successfully.');
        print(' [IncidentPage] Auto-filled City: $cityName');
        print(' [IncidentPage] Auto-filled Centre: $centreName');
        print(
          ' [IncidentPage] Found ${courseCodes.length} course codes: $courseCodes',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Student details loaded successfully.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        print(' [IncidentPage] Result was not success: ${result['error']}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Student record not found.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print(' [IncidentPage] Exception in _fetchStudentDetails: $e');
      if (mounted) {
        setState(() {
          _isLoadingStudentDetails = false;
        });
      }
    }
  }

  /// Shared method to fetch and display the course name
  Future<void> _fetchCourseName(String fullCourseCode) async {
    print(
      ' [IncidentPage] >>> STEP: Fetching course name for: "$fullCourseCode"',
    );

    setState(() {
      _isLoadingCourseName = true;
    });

    try {
      final result = await CourseNameService.getCourseName(fullCourseCode);

      if (!mounted) return;

      setState(() {
        _isLoadingCourseName = false;
        if (result['success'] == true) {
          courseNameController.text = result['courseName'] ?? '';
        } else {
          print(
            ' [IncidentPage] Course name search failed: ${result['error']}',
          );
          courseNameController.text = 'Course name not found';
        }
      });
    } catch (e) {
      print(' [IncidentPage] Exception in _fetchCourseName: $e');
      if (mounted) {
        setState(() {
          _isLoadingCourseName = false;
        });
      }
    }
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
                "Incident Report",
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Main content
          SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // First Row: Student ID and Student Name
                Row(
                  children: [
                    Expanded(child: _buildStudentIdField()),
                    SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        label: "Student Name",
                        controller: studentNameController,
                        hint: "Enter Student Name",
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 20),

                // Second Row: Course Code and Course Name
                Row(
                  children: [
                    Expanded(child: _buildCourseCodeField()),
                    SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        label: "Course Name",
                        controller: courseNameController,
                        hint: "Enter Course Name",
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 20),

                // Third Row: CITY  Name and Centre Name
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        label: "City Name",
                        controller: cityNameController,
                        hint: "Enter City Name",
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        label: "Centre Name",
                        controller: centreNameController,
                        hint: "Enter Centre Name",
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 24),

                // Nature of UFM Dropdown
                _buildDropdown(
                  label: "Nature of UFM",
                  value: selectedUFM,
                  items: ufmOptions,
                  hint: "Select UFM Type",
                  onChanged: (value) {
                    setState(() {
                      selectedUFM = value;
                    });
                  },
                ),

                // Conditional "Any other" details text field
                if (selectedOffence == 'Any other (give details below)') ...[
                  SizedBox(height: 20),
                  _buildTextField(
                    label: "Please specify details",
                    controller: anyOtherDetailsController,
                    hint: "Enter details about the UFM",
                  ),
                ],

                SizedBox(height: 20),

                // Types of Offence Dropdown
                _buildDropdown(
                  label: "Types of Offence",
                  value: selectedOffence,
                  items: offenceOptions,
                  hint: "Select Offence Type",
                  onChanged: (value) {
                    setState(() {
                      selectedOffence = value;
                    });
                  },
                ),

                SizedBox(height: 24),

                // Description Text Area
                Text(
                  "Observer / Super Proctor Comments",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  "(Description of the incident)",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color.fromARGB(221, 109, 107, 107),
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: "Enter incident description...",
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.blue.shade300),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),

                SizedBox(height: 32),

                // Scan Incident Report Button (Light Blue)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      // Handle scan incident report
                      _handleScanIncidentReport();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.blue.shade200),
                      ),
                    ),
                    child: Text(
                      "Scan Incident Report",
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

          // Loading overlay with blur
          if (_isLoadingStudentDetails || _isLoadingCourseName)
            Container(
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
                        _isLoadingStudentDetails
                            ? 'Loading student details...'
                            : 'Loading course name...',
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
        ],
      ),
      bottomNavigationBar: const AppFooter(),
    );
  }

  Widget _buildStudentIdField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Student ID",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8),
        Stack(
          children: [
            TextField(
              controller: studentIdController,
              focusNode: studentIdFocusNode,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: "Click to select or type to search",
                hintStyle: TextStyle(color: Colors.grey.shade400),
                suffixIcon: _allStudentIds.isNotEmpty
                    ? Icon(
                        _showDropdown
                            ? Icons.arrow_drop_up
                            : Icons.arrow_drop_down,
                        color: Colors.grey.shade600,
                      )
                    : (_isLoadingStudentIds
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            )
                          : null),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.blue.shade300),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        // Dropdown
        if (_showDropdown) ...[
          SizedBox(height: 4),
          Container(
            constraints: BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: _filteredStudentIds.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        "No matching students found",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _filteredStudentIds.length,
                    itemBuilder: (context, index) {
                      final studentId = _filteredStudentIds[index];
                      final query = studentIdController.text
                          .trim()
                          .toUpperCase();

                      return InkWell(
                        onTap: () async {
                          setState(() {
                            studentIdController.text = studentId;
                            _showDropdown = false;
                          });
                          studentIdFocusNode.unfocus();

                          // Auto-fill student name and centre
                          await _fetchStudentDetails(studentId);
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: index < _filteredStudentIds.length - 1
                                  ? BorderSide(color: Colors.grey.shade200)
                                  : BorderSide.none,
                            ),
                          ),
                          child: _buildHighlightedText(studentId, query),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(text);
    }

    final matchLength = query.length;
    final matchedPart = text.substring(0, matchLength);
    final remainingPart = text.substring(matchLength);

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: matchedPart,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              fontSize: 15,
            ),
          ),
          TextSpan(
            text: remainingPart,
            style: TextStyle(
              fontWeight: FontWeight.normal,
              color: Colors.grey.shade500,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseCodeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Course Code",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8),
        Stack(
          children: [
            TextField(
              controller: courseCodeController,
              focusNode: courseCodeFocusNode,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: _availableCourseCodes.isEmpty
                    ? "Select student first"
                    : "Click to select or type to search",
                hintStyle: TextStyle(color: Colors.grey.shade400),
                suffixIcon: _availableCourseCodes.isNotEmpty
                    ? Icon(
                        _showCourseDropdown
                            ? Icons.arrow_drop_up
                            : Icons.arrow_drop_down,
                        color: Colors.grey.shade600,
                      )
                    : null,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.blue.shade300),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        // Dropdown
        if (_showCourseDropdown && _filteredCourseCodes.isNotEmpty) ...[
          SizedBox(height: 4),
          Container(
            constraints: BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _filteredCourseCodes.length,
              itemBuilder: (context, index) {
                final courseCode = _filteredCourseCodes[index];

                return InkWell(
                  onTap: () async {
                    setState(() {
                      courseCodeController.text = courseCode;
                      _showCourseDropdown = false;
                    });
                    courseCodeFocusNode.unfocus();

                    // Fetch course name using the shared method
                    await _fetchCourseName(courseCode);
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: index < _filteredCourseCodes.length - 1
                            ? BorderSide(color: Colors.grey.shade200)
                            : BorderSide.none,
                      ),
                    ),
                    child: Text(courseCode, style: TextStyle(fontSize: 15)),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.blue.shade300),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required String hint,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true, // Prevents overflow
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.blue.shade300),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis, maxLines: 2),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _handleScanIncidentReport() {
    // Validate all fields before opening camera
    if (studentIdController.text.isEmpty ||
        studentNameController.text.isEmpty ||
        courseCodeController.text.isEmpty ||
        courseNameController.text.isEmpty ||
        cityNameController.text.isEmpty ||
        centreNameController.text.isEmpty ||
        selectedUFM == null ||
        selectedOffence == null ||
        descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please fill in all required fields before scanning."),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    // Validate "Any other" details if that option is selected
    if (selectedOffence == 'Any other (give details below)' &&
        anyOtherDetailsController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please provide details for the 'Any other' offence description."),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    // Prepare form data
    final formData = {
      'studentId': studentIdController.text,
      'studentName': studentNameController.text,
      'courseCode': courseCodeController.text,
      'session': _courseSessionMap[courseCodeController.text] ?? '',
      'courseName': courseNameController.text,
      'cityName': cityNameController.text,
      'centreName': centreNameController.text,
      'ufm': selectedUFM!,
      'offence': selectedOffence!,
      'offenceDetails': selectedOffence == 'Any other (give details below)'
          ? anyOtherDetailsController.text
          : '',
      'description': descriptionController.text,
    };

    // Navigate to camera capture flow
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraCaptureFlow(formData: formData),
      ),
    );
  }
}
