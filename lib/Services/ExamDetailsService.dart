// ignore_for_file: empty_catches, curly_braces_in_flow_control_structures, avoid_print, file_names

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:supervisorapp/Services/auth/supervisor_auth_service.dart';
import 'package:supervisorapp/Services/storage/s3_transfer_helper.dart';
import '../core/network/api_client.dart';

class ExamDetailsService {
  // S3 Configuration
  static const String _bucketName = 'bitsexamapp';
  static const String _excelFilePath = 'student_details/BITS-exam.csv';
  static const String _timingExcelFilePath = 'exam_details/ExamDetails.csv';

  // Cache variables
  static List<List<dynamic>>? _cachedSheet;
  static Map<String, Map<String, String>>? _cachedTimetable;
  static DateTime? _cacheTimestamp;
  static DateTime? _timingCacheTimestamp;
  static const Duration _cacheDuration = Duration(minutes: 2);

  /// Fetch and parse exam details for a student
  /// This method now validates in two steps:
  /// 1. Check if student ID exists
  /// 2. Check if student has exams today
  static Future<Map<String, dynamic>> getStudentExamDetails(
    String studentId,
  ) async {
    print(' getStudentExamDetails called for ID: $studentId');
    try {
      // Add timeout to prevent long waits (reduced to 8 seconds)
      return await _getStudentExamDetailsInternal(studentId)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print(' Request timed out after 8 seconds');
              return {
                'success': false,
                'error':
                    'Request timed out. Please check your internet connection and try again.',
                'errorType': 'timeout',
              };
            },
          )
          .catchError((error) {
            print(' Error caught in getStudentExamDetails: $error');
            return {
              'success': false,
              'error': 'Failed to load exam details. Please try again.',
              'errorType': 'exception',
            };
          });
    } catch (e) {
      print('Error in getStudentExamDetails: $e');
      return {
        'success': false,
        'error':
            'Unable to load exam information. Please check your internet connection.',
        'errorType': 'exception',
      };
    }
  }

  /// Helper to download and parse student sheet robustly
  static Future<List<List<dynamic>>> _getAndParseStudentSheet() async {
    // 1. Check cache
    if (_cachedSheet != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < _cacheDuration) {
      return _cachedSheet!;
    }

    print(' [ExamDetails] Downloading student sheet from S3...');
    final csvData = await _downloadCsvFromS3();
    if (csvData == null || csvData.isEmpty) return [];

    // 2. Robust manual line splitting followed by CSV parsing per line
    // This is more reliable for files with mixed or unusual line endings
    final lines = csvData.split(RegExp(r'\r\n|\n|\r'));
    List<List<dynamic>> sheet = [];

    final converter = const CsvToListConverter();
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final row = converter.convert(line);
        if (row.isNotEmpty) {
          sheet.add(row[0]);
        }
      } catch (e) {
        // Skip malformed lines
      }
    }

    if (sheet.isNotEmpty) {
      _cachedSheet = sheet;
      _cacheTimestamp = DateTime.now();
      print(' [ExamDetails] Sheet loaded with ${sheet.length} rows.');
    }

    return sheet;
  }

  /// Batch lookup of centers for a list of student IDs.
  /// Returns a map of {studentId: centerName}
  static Future<Map<String, String>> getStudentCentres(
    List<String> studentIds,
  ) async {
    Map<String, String> results = {};
    if (studentIds.isEmpty) return results;

    try {
      // 1. Ensure sheet is loaded
      final sheet = await _getAndParseStudentSheet();
      if (sheet.isEmpty) return results;

      print(' [ExamDetails] Sheet loaded with ${sheet.length} rows.');

      // 2. Identify columns
      final headerRow = sheet[0];
      print(
        ' [ExamDetails] Header row found with ${headerRow.length} columns.',
      );
      int? bitsIdCol;
      int? centreCol;

      for (int i = 0; i < headerRow.length; i++) {
        final cellValue = headerRow[i]?.toString().trim().toUpperCase() ?? '';

        // Strict and Lenient matching for BITS ID
        if (cellValue == 'BITS ID' ||
            cellValue == 'BITSID' ||
            (cellValue.contains('BITS') && cellValue.contains('ID'))) {
          bitsIdCol = i;
          print(
            ' [ExamDetails] Matched BITS ID column at index $i ($cellValue)',
          );
        }
        // Strict and Lenient matching for Center (checking both CENTER and CENTRE)
        else if (cellValue == 'CENTER' ||
            cellValue == 'CENTRE' ||
            cellValue.startsWith('CENTER') ||
            cellValue.startsWith('CENTRE')) {
          centreCol = i;
          print(
            ' [ExamDetails] Matched Center column at index $i ($cellValue)',
          );
        }
      }

      if (bitsIdCol == null || centreCol == null) return results;

      // 3. Optimized search
      final Set<String> searchSet = studentIds
          .map((id) => id.trim().toLowerCase())
          .toSet();

      for (int i = 1; i < sheet.length; i++) {
        final row = sheet[i];
        if (row.length <= bitsIdCol) continue;

        final bitsId = row[bitsIdCol]?.toString().trim() ?? '';
        final normalizedId = bitsId.toLowerCase();

        if (searchSet.contains(normalizedId)) {
          final center = row.length > centreCol
              ? row[centreCol]?.toString().trim() ?? 'Unknown'
              : 'Unknown';
          results[normalizedId] = center;

          // If we found everything, stop
          if (results.length >= searchSet.length) break;
        }
      }
    } catch (e, stack) {
      print(' [ExamDetails] Error in getStudentCentres: $e');
      print(' [ExamDetails] Stack trace: $stack');
    }

    return results;
  }

  /// Get ALL unique student IDs from the master CSV database
  static Future<List<String>> getAllStudentIds({String? centerFilter}) async {
    try {
      final sheet = await _getAndParseStudentSheet();
      if (sheet.isEmpty) return [];

      final headerRow = sheet[0];
      int? bitsIdCol;
      int? centerCol;
      List<int> todayExamCols = [];

      final today = DateTime.now();
      final dateFormats = [
        DateFormat('dd-MM-yyyy').format(today),
        DateFormat('d-M-yyyy').format(today),
        DateFormat('dd/MM/yyyy').format(today),
        DateFormat('d/M/yyyy').format(today),
        DateFormat('yyyy-MM-dd').format(today),
      ];

      for (int i = 0; i < headerRow.length; i++) {
        final cellValue = headerRow[i]?.toString().trim() ?? '';
        final upperValue = cellValue.toUpperCase();

        if (upperValue == 'BITS ID' ||
            upperValue == 'BITSID' ||
            (upperValue.contains('BITS') && upperValue.contains('ID'))) {
          bitsIdCol = i;
        } else if (upperValue == 'CENTER' || upperValue == 'CENTRE') {
          centerCol = i;
        } else {
          // Check if it's an exam column for today
          for (var dateFormat in dateFormats) {
            if (cellValue.contains(dateFormat)) {
              todayExamCols.add(i);
              break;
            }
          }
        }
      }

      if (bitsIdCol == null) return [];

      final normalizedFilter = centerFilter?.trim().toUpperCase();
      Set<String> allIds = {};

      for (int i = 1; i < sheet.length; i++) {
        final row = sheet[i];
        if (row.length > bitsIdCol) {
          // 1. Filter by Center
          if (normalizedFilter != null &&
              centerCol != null &&
              row.length > centerCol) {
            final studentCenter =
                row[centerCol]?.toString().trim().toUpperCase() ?? '';
            if (studentCenter != normalizedFilter) continue;
          }

          // 2. Filter by Today's Exams (must have a value in at least one todayExamCol)
          bool hasExamToday = false;
          if (todayExamCols.isEmpty) {
            hasExamToday =
                true; // Fallback: if no date columns found, include anyway
          } else {
            for (var colIdx in todayExamCols) {
              if (row.length > colIdx) {
                final cellValue = row[colIdx]?.toString().trim() ?? '';
                if (cellValue.isNotEmpty) {
                  hasExamToday = true;
                  break;
                }
              }
            }
          }

          if (!hasExamToday) continue;

          final id = row[bitsIdCol]?.toString().trim() ?? '';
          if (id.isNotEmpty) {
            allIds.add(id);
          }
        }
      }

      return allIds.toList()..sort();
    } catch (e) {
      print(' [ExamDetails] Error in getAllStudentIds: $e');
      return [];
    }
  }

  /// Internal method for fetching student exam details
  static Future<Map<String, dynamic>> _getStudentExamDetailsInternal(
    String studentId,
  ) async {
    try {
      final startTime = DateTime.now();
      print('Fetching exam details for student: $studentId');

      // Check cache first
      final cachedSheet = _cachedSheet;
      final cachedTimestamp = _cacheTimestamp;
      if (cachedSheet != null &&
          cachedTimestamp != null &&
          DateTime.now().difference(cachedTimestamp) < _cacheDuration) {
        print(
          ' [ExamDetails] Using cached exam data (Age: ${DateTime.now().difference(cachedTimestamp).inMinutes} mins)',
        );

        // Step 1: Validate student ID first
        final studentValidation = _validateStudentExists(
          cachedSheet,
          studentId,
        );
        if (!studentValidation['exists']) {
          print(' [ExamDetails] Student ID not found (cached check).');
          return {
            'success': false,
            'error': 'Student ID not found.',
            'errorType': 'student_not_found',
          };
        }

        // Step 2: Ensure timetable is also loaded
        if (_cachedTimetable == null ||
            _timingCacheTimestamp == null ||
            DateTime.now().difference(_timingCacheTimestamp!) >
                _cacheDuration) {
          print(' [ExamDetails] Timetable cache empty/expired, loading...');
          final timingData = await _downloadCsvFromS3(
            path: _timingExcelFilePath,
          );
          if (timingData != null) {
            final timingSheet = const CsvToListConverter().convert(timingData);
            _cachedTimetable = _extractExamTimings(timingSheet);
            _timingCacheTimestamp = DateTime.now();
          }
        }

        // Step 3: Check for today's exams
        final result = _extractStudentExams(cachedSheet, studentId);
        print(
          ' [ExamDetails] Total search time (cached): ${DateTime.now().difference(startTime).inMilliseconds}ms',
        );
        return result;
      }

      print('Cache empty or expired, downloading from S3...');

      // Step 1: Download and parse student sheet robustly
      final sheet = await _getAndParseStudentSheet();

      if (sheet.isEmpty) {
        print(' [ExamDetails] ERROR: Failed to load student sheet');
        return {
          'success': false,
          'error': 'Failed to load student database.',
          'errorType': 'download_error',
        };
      }

      print(' [ExamDetails] Sheet has ${sheet.length} rows');
      print(
        ' [ExamDetails] Step 3: Starting student validation for $studentId...',
      );

      // Step 3: Validate student ID FIRST before checking exam dates
      final validationStartTime = DateTime.now();
      print('Calling _validateStudentExists for: $studentId');

      final studentValidation = _validateStudentExists(sheet, studentId);

      print(
        'Student validation took: ${DateTime.now().difference(validationStartTime).inMilliseconds}ms',
      );

      if (!studentValidation['exists']) {
        print(' Student ID not found');
        return {
          'success': false,
          'error': 'Student ID not found',
          'errorType': 'student_not_found',
        };
      }

      print(' Student ID validated: ${studentValidation['studentName']}');

      // Check if timetable needs loading
      final currentTimetable = _cachedTimetable;
      final currentTimingTimestamp = _timingCacheTimestamp;

      if (currentTimetable == null ||
          currentTimetable.isEmpty ||
          currentTimingTimestamp == null ||
          DateTime.now().difference(currentTimingTimestamp) > _cacheDuration) {
        print(
          ' [ExamDetails] Refreshing timetable from S3: $_timingExcelFilePath',
        );
        final timingCsv = await _downloadCsvFromS3(path: _timingExcelFilePath);

        if (timingCsv != null) {
          final timingData = const CsvToListConverter().convert(timingCsv);
          print(' [ExamDetails] Parsing fresh timetable...');
          _cachedTimetable = _extractExamTimings(timingData);
          _timingCacheTimestamp = DateTime.now();
          print(
            ' [ExamDetails] Timetable extraction complete. Cached timings for ${(_cachedTimetable ?? {}).length} courses',
          );
        } else {
          print(
            ' [ExamDetails] WARN: Failed to download dedicated timing file.',
          );
          _cachedTimetable = {};
        }
      } else {
        print(
          ' [ExamDetails] Using cached timetable with ${currentTimetable.length} entries',
        );
      }

      // Step 4: Now check for today's exams
      final searchStartTime = DateTime.now();
      final result = _extractStudentExams(sheet, studentId);
      print(
        'Exam search took: ${DateTime.now().difference(searchStartTime).inMilliseconds}ms',
      );

      print(
        'Total processing time (fresh): ${DateTime.now().difference(startTime).inSeconds}s',
      );
      return result;
    } catch (e) {
      print('Error in getStudentExamDetails: $e');
      return {
        'success': false,
        'error':
            'Unable to load exam information. Please check your internet connection.',
        'errorType': 'exception',
      };
    }
  }

  /// Validate if student ID exists in the sheet (fast check)
  static Map<String, dynamic> _validateStudentExists(
    List<List<dynamic>> sheet,
    String studentId,
  ) {
    try {
      print('_validateStudentExists: Starting validation');

      // Find header row (row 0)
      final headerRow = sheet[0];
      print(
        '_validateStudentExists: Header row has ${headerRow.length} columns',
      );

      // Find BITS ID column
      int? bitsIdCol;
      int? nameCol;

      for (int i = 0; i < headerRow.length; i++) {
        final cellValue = headerRow[i]?.toString().trim() ?? '';
        if (cellValue.toUpperCase() == 'BITS ID') {
          bitsIdCol = i;
          print('_validateStudentExists: Found BITS ID column at index $i');
        } else if (cellValue.toUpperCase() == 'NAME') {
          nameCol = i;
          print('_validateStudentExists: Found NAME column at index $i');
        }
      }

      if (bitsIdCol == null) {
        print('_validateStudentExists: ERROR - BITS ID column not found');
        return {
          'exists': false,
          'error': 'Invalid exam data format. Please contact support.',
        };
      }

      // Search for student ID
      final searchId = studentId.trim().toLowerCase();
      print(
        '_validateStudentExists: Searching for "$searchId" in ${sheet.length} rows',
      );

      for (int rowIndex = 1; rowIndex < sheet.length; rowIndex++) {
        // Log progress every 100 rows
        if (rowIndex % 100 == 0) {
          print('_validateStudentExists: Checked $rowIndex rows...');
        }

        final row = sheet[rowIndex];
        if (row.length <= bitsIdCol) continue;

        final rowStudentId = row[bitsIdCol]?.toString().trim() ?? '';
        final currentId = rowStudentId.toLowerCase();

        if (currentId == searchId) {
          final studentName = nameCol != null && row.length > nameCol
              ? row[nameCol]?.toString().trim() ?? 'Unknown'
              : 'Unknown';

          print('_validateStudentExists:  Found student at row $rowIndex');
          return {
            'exists': true,
            'studentName': studentName,
            'rowIndex': rowIndex,
          };
        }
      }

      print(
        '_validateStudentExists:  Student not found after checking all ${sheet.length} rows',
      );
      return {'exists': false, 'error': 'Student ID not found'};
    } catch (e) {
      print('Error validating student: $e');
      return {
        'exists': false,
        'error': 'Failed to validate student. Please try again.',
      };
    }
  }

  /// Get available question slots (Q1, Q2, etc.) from S3
  /// Get available question slots (Q1, Q2, etc.) from S3 via consolidated backend
  static Future<List<String>> getQuestionSlots({
    required String fullCourseCode,
    required String date,
  }) async {
    try {
      final formattedCode = _formatCourseCode(fullCourseCode);
      print('Fetching slots for $formattedCode on $date via backend');

      final response = await ApiClient.sendAction(
        action: 'getQuestionSlots',
        payload: {'courseCode': formattedCode, 'date': date},
      );

      if (response['success'] == true && response['slots'] != null) {
        final List rawSlots = response['slots'] as List;
        final List<String> slots = rawSlots.map((s) => s.toString()).toList();
        print('Found ${slots.length} slots: $slots');
        return slots;
      }
      return [];
    } catch (e) {
      print('Error fetching question slots: $e');
      return [];
    }
  }

  /// Format course code for S3 path: "DUMMZA110-EC3R" -> "DUMM ZA110-EC3R"
  /// If the code already contains a space (already formatted), returns as-is.
  static String _formatCourseCode(String code) {
    if (code.isEmpty) return code;

    // If already has a space before Z, return as-is
    if (code.contains(' ')) return code;

    // Rule: Insert a space just before the 'Z' character that precedes the numeric part.
    // e.g., "DUMMZA110-EC3R" -> "DUMM ZA110-EC3R"
    final zIndex = code.indexOf(RegExp(r'[Zz]'));
    if (zIndex > 0) {
      return '${code.substring(0, zIndex)} ${code.substring(zIndex)}';
    }

    return code;
  }

  /// Download CSV file from S3 using pre-signed GET URL via S3Helper
  static Future<String?> _downloadCsvFromS3({String? path}) async {
    final targetPath = path ?? _excelFilePath;
    try {
      print('Downloading CSV from S3: $_bucketName/$targetPath');

      final bytes = await S3Helper.download(
        bucket: _bucketName,
        key: targetPath,
      );

      if (bytes != null) {
        print('CSV file downloaded successfully: $targetPath');
        return utf8.decode(bytes, allowMalformed: true);
      }
      return null;
    } catch (e) {
      print(' Error downloading CSV from S3 ($targetPath): $e');
      return null;
    }
  }

  /// Extract student exam details from CSV sheet
  /// Optimized to check student ID FIRST before parsing exam dates
  static Future<Map<String, dynamic>> _extractStudentExams(
    List<List<dynamic>> sheet,
    String studentId,
  ) async {
    try {
      // Find header row (row 0)
      final headerRow = sheet[0];

      // STEP 1: Find BITS ID, Name, and Centre columns first
      int? bitsIdCol;
      int? nameCol;
      int? centreCol;

      print('Parsing basic columns...');
      for (int i = 0; i < headerRow.length; i++) {
        final cellValue = headerRow[i]?.toString().trim() ?? '';
        if (cellValue.isEmpty) continue;

        if (cellValue.toUpperCase() == 'BITS ID') {
          bitsIdCol = i;
          print('Found BITS ID at column $i');
        } else if (cellValue.toUpperCase() == 'NAME') {
          nameCol = i;
          print('Found Name at column $i');
        } else if (cellValue.toUpperCase() == 'CENTER' ||
            cellValue.toUpperCase() == 'CENTRE') {
          centreCol = i;
          print('Found Centre at column $i');
        }
      }

      if (bitsIdCol == null || nameCol == null || centreCol == null) {
        print(
          'Error: Missing required columns. BITS ID: $bitsIdCol, Name: $nameCol, Centre: $centreCol',
        );
        return {
          'success': false,
          'error': 'Invalid exam data format. Please contact support.',
          'errorType': 'parse_error',
        };
      }

      // STEP 2: Find student row FIRST (before parsing exam dates)
      print('Searching for student: "$studentId"');
      final searchId = studentId.trim().toLowerCase();

      int? studentRowIndex;
      String? studentName;
      String? centre;

      for (int rowIndex = 1; rowIndex < sheet.length; rowIndex++) {
        final row = sheet[rowIndex];
        if (row.length <= bitsIdCol) continue;

        final rowStudentId = row[bitsIdCol]?.toString().trim() ?? '';
        final currentId = rowStudentId.toLowerCase();

        if (currentId == searchId) {
          // Student found!
          studentRowIndex = rowIndex;
          studentName = row.length > nameCol
              ? row[nameCol]?.toString().trim() ?? ''
              : 'Unknown';
          centre = row.length > centreCol
              ? row[centreCol]?.toString().trim() ?? ''
              : 'Unknown';

          print(
            ' Student found at row $rowIndex: $studentName ($rowStudentId)',
          );
          break;
        }
      }

      // If student not found, return immediately
      if (studentRowIndex == null) {
        print(' Student ID not found');
        return {
          'success': false,
          'error': 'Student ID not found.',
          'errorType': 'student_not_found',
        };
      }

      // STEP 3: NOW parse exam date columns (only after student is validated)
      print('Student validated! Now checking for today\'s exams...');

      final today = DateTime.now();
      final dateFormats = [
        DateFormat('dd-MM-yyyy').format(today),
        DateFormat('d-M-yyyy').format(today),
        DateFormat('dd/MM/yyyy').format(today),
        DateFormat('d/M/yyyy').format(today),
        DateFormat('yyyy-MM-dd').format(today),
      ];
      print('Today\'s dates to check: $dateFormats');

      List<Map<String, dynamic>> examColumns = [];

      // Parse headers for exam columns
      for (int i = 0; i < headerRow.length; i++) {
        final cellValue = headerRow[i]?.toString().trim() ?? '';
        if (cellValue.isEmpty) continue;

        // Check if this column contains any of our date formats
        bool isExamColumn = false;
        for (var dateFormat in dateFormats) {
          if (cellValue.contains(dateFormat)) {
            isExamColumn = true;
            break;
          }
        }

        if (isExamColumn) {
          // This is an exam column for today
          // Expecting format like: C1_29-12-2025_AN or just containing the date
          final parts = cellValue.split('_');
          if (parts.length >= 3) {
            examColumns.add({
              'columnIndex': i,
              'examNumber': parts[0], // C1, C2, etc.
              'date': parts[1],
              'session': parts[2], // AN or FN
              'columnName': cellValue,
            });
            print('Found Exam column at $i: $cellValue');
          } else if (cellValue.contains(dateFormats[0])) {
            // Fallback if underscores are missing but date matches first format
            examColumns.add({
              'columnIndex': i,
              'examNumber': 'Exam',
              'date': dateFormats[0],
              'session': 'AN/FN',
              'columnName': cellValue,
            });
            print('Found potential Exam column at $i: $cellValue');
          }
        }
      }

      print('Found ${examColumns.length} exam columns for today');

      // STEP 4: Extract today's exams for the validated student
      final studentRow = sheet[studentRowIndex];
      List<Map<String, String>> todaysExams = [];

      print(' Student row has ${studentRow.length} columns');
      print(' Checking ${examColumns.length} exam columns...');

      for (var examCol in examColumns) {
        final colIdx = examCol['columnIndex'];
        print('   Checking column $colIdx (${examCol['columnName']})');

        if (studentRow.length <= colIdx) {
          print('     Student row too short (${studentRow.length} <= $colIdx)');
          continue;
        }

        final cellValue = studentRow[colIdx];
        final courseCodeRaw = cellValue?.toString().trim() ?? '';

        print('     Cell value: "$cellValue" (type: ${cellValue.runtimeType})');
        print('     Trimmed: "$courseCodeRaw"');

        if (courseCodeRaw.isNotEmpty) {
          // The courseCodeRaw is just the course code from student sheet (e.g., "DUMMZA110")
          // We'll look up the exam type from the timetable later
          final courseCode = courseCodeRaw.trim();

          todaysExams.add({
            'examNumber': examCol['examNumber'],
            'session': examCol['session'],
            'courseCode': courseCode,
            'fullCourseCode':
                courseCode, // Will be updated with exam type later
          });
          print('     Added exam: $courseCode');
        } else {
          print('     Cell is empty - no exam scheduled in this slot');
        }
      }

      print('Found ${todaysExams.length} exams for today');

      if (todaysExams.isEmpty) {
        return {
          'success': false,
          'error': 'No exam scheduled for today',
          'errorType': 'no_exam',
          'studentName': studentName,
          'centre': centre,
        };
      }

      // Fetch timings from DynamoDB
      Map<String, String> dbTimings = {};
      try {
        final dbService = DynamoDBService();
        final timingResult = await dbService.getCenterTimings(centre!);
        if (timingResult['success'] == true) {
          dbTimings = timingResult['data'];
          print(' [ExamDetails] Fetched timings from DynamoDB for $centre');
        }
      } catch (e) {
        print(' [ExamDetails] Error fetching DynamoDB timings: $e');
      }

      // Merge with Timetable/Timings and construct fullCourseCode
      final currentTimetable = _cachedTimetable;
      for (var exam in todaysExams) {
        final courseCode = exam['courseCode']?.toString().toUpperCase();
        if (courseCode == null) continue;

        final session = exam['session']?.toString().toUpperCase() ?? '';

        // 1. Get Start/End Times from DynamoDB (Prioritize this)
        if (session.isNotEmpty) {
          final startTime = dbTimings['${session}_start'] ?? '';
          final endTime = dbTimings['${session}_end'] ?? '';
          if (startTime.isNotEmpty) exam['examStartTime'] = startTime;
          if (endTime.isNotEmpty) exam['examEndTime'] = endTime;
        }

        // 2. Get Exam Type and Course Name from CSV Timetable (Fallback for timings if needed)
        Map<String, String>? csvInfo;
        final normalizedSearchCode = courseCode
            .split('-')
            .first
            .replaceAll(' ', '')
            .toUpperCase();
        if (currentTimetable != null &&
            currentTimetable.containsKey(normalizedSearchCode)) {
          csvInfo = currentTimetable[normalizedSearchCode];
        }

        if (csvInfo != null) {
          if (exam['examStartTime'] == null)
            exam['examStartTime'] = csvInfo['start'] ?? '';
          if (exam['examEndTime'] == null)
            exam['examEndTime'] = csvInfo['end'] ?? '';

          final examType = csvInfo['examType'] ?? '';
          if (examType.isNotEmpty) {
            exam['examType'] = examType;
            final formattedBaseCode = _formatCourseCode(courseCode);
            exam['fullCourseCode'] = formattedBaseCode.contains(examType)
                ? formattedBaseCode
                : '$formattedBaseCode-$examType';
          } else {
            exam['fullCourseCode'] = _formatCourseCode(courseCode);
          }
          exam['courseName'] = csvInfo['courseName'] ?? '';
        } else {
          exam['fullCourseCode'] = _formatCourseCode(courseCode);
        }
      }

      return {
        'success': true,
        'studentId': studentId,
        'studentName': studentName,
        'centre': centre,
        'exams': todaysExams,
      };
    } catch (e) {
      print('Error extracting student exams: $e');
      return {
        'success': false,
        'error': 'Unable to read exam data. Please try again later.',
        'errorType': 'parse_error',
      };
    }
  }

  /// Extract exam timings from CSV data
  static Map<String, Map<String, String>> _extractExamTimings(
    List<List<dynamic>> sheet,
  ) {
    Map<String, Map<String, String>> timetable = {};

    try {
      if (sheet.isEmpty) return timetable;

      int? courseCodeCol;
      int? examTimeCol;
      int? examTypeCol;
      int? courseNameCol;

      // Try header detection
      final headerRow = sheet[0];
      print('    Scanning headers for timetable...');
      for (int i = 0; i < headerRow.length; i++) {
        final val = headerRow[i]?.toString().trim().toUpperCase() ?? '';
        if (val.isEmpty) continue;

        final sanitizedVal = val.replaceAll(' ', '').replaceAll('_', '');
        if (sanitizedVal == 'COURSECODE' ||
            (val.contains('COURSE') && val.contains('CODE'))) {
          courseCodeCol = i;
        } else if (sanitizedVal == 'COURSENAME' ||
            (val.contains('COURSE') && val.contains('NAME'))) {
          courseNameCol = i;
        } else if (sanitizedVal == 'EXAMTIME' ||
            val == 'TIMING' ||
            (val.contains('EXAM') && val.contains('TIME'))) {
          examTimeCol = i;
        } else if (sanitizedVal == 'EXAMTYPE' ||
            (val.contains('EXAM') && val.contains('TYPE'))) {
          examTypeCol = i;
        }
      }

      // Fallback
      if (courseCodeCol == null) {
        courseCodeCol = 1;
        courseNameCol = 2;
        examTypeCol = 4;
        examTimeCol = 5;
      }

      for (int i = 1; i < sheet.length; i++) {
        final row = sheet[i];
        if (row.length <= courseCodeCol) continue;

        final code = row[courseCodeCol]?.toString().trim();
        final courseName = (courseNameCol != null && row.length > courseNameCol)
            ? row[courseNameCol]?.toString().trim()
            : null;
        var timeStr = (examTimeCol != null && row.length > examTimeCol)
            ? row[examTimeCol]?.toString().trim()
            : null;
        final examType = examTypeCol != null && row.length > examTypeCol
            ? row[examTypeCol]?.toString().trim()
            : null;

        if (code != null && code.isNotEmpty) {
          final Map<String, String> entryData = {};

          if (timeStr != null && timeStr.isNotEmpty) {
            final parsed = _parseExamTimeRange(timeStr);
            if (parsed != null) entryData.addAll(parsed);
          }

          if (examType != null && examType.isNotEmpty) {
            entryData['examType'] = examType;
          }

          if (courseName != null && courseName.isNotEmpty) {
            entryData['courseName'] = courseName;
          }

          final normalizedCode = code.toUpperCase().replaceAll(' ', '');
          timetable[normalizedCode] = entryData;
        }
      }
    } catch (e) {
      print(' Error in _extractExamTimings: $e');
    }
    return timetable;
  }

  static Map<String, String>? _parseExamTimeRange(String raw) {
    try {
      print('       Parsing: "$raw"');
      // Split by dash and extract digits:digits
      final parts = raw.split('-');
      if (parts.length < 2) return null;

      final timeRegex = RegExp(r'(\d{1,2}:\d{2})');

      final startMatch = timeRegex.firstMatch(parts[0]);
      final endMatch = timeRegex.firstMatch(parts[1]);

      if (startMatch != null && endMatch != null) {
        final start = startMatch.group(1) ?? '00:00';
        final end = endMatch.group(1) ?? '00:00';
        print('          Parsed: $start - $end');
        return {'start': '$start:00', 'end': '$end:00'};
      }
    } catch (e) {
      print('       Error parsing "$raw": $e');
    }
    return null;
  }

  /// Fetches currently active exams for a center.
  ///
  /// Step 1 — CSV: find today's session columns for this centre → get session (FN/AN/EN) + course codes.
  /// Step 2 — DynamoDB: look up the timing for those sessions.
  /// Step 3 — Time check: is current time within the session window?
  static Future<List<Map<String, dynamic>>> getCenterActiveExams(
    String centre,
  ) async {
    try {
      // ── Step 1: Read the student sheet ───────────────────────────────────
      final sheet = await _getAndParseStudentSheet();
      if (sheet.isEmpty) {
        print(' [ExamDetails] getCenterActiveExams: student sheet is empty');
        return [];
      }

      final header = sheet[0];

      // Find Centre column (CSV uses "Center" but we upper-case both sides)
      final centreCol = _findColumnIndex(header, [
        'CENTER',
        'CENTRE',
        'EXAM HALL',
      ]);
      final bitsIdCol = _findColumnIndex(header, ['BITS ID', 'BITSID']);

      if (centreCol == null || bitsIdCol == null) {
        print(
          ' [ExamDetails] getCenterActiveExams: CENTER or BITS ID column not found in CSV',
        );
        return [];
      }

      // Today in the format used by the CSV header: dd-MM-yyyy
      final today = DateFormat('dd-MM-yyyy').format(DateTime.now());

      // Find all exam columns for today, grouped by session
      // Column format: C1_27-04-2026_FN  (session is the last segment after '_')
      final Map<String, List<int>> sessionToColIndexes = {}; // e.g. 'FN' → [5]
      for (int j = 0; j < header.length; j++) {
        final colName = header[j]?.toString().trim().toUpperCase() ?? '';
        if (!colName.contains(today.toUpperCase())) continue;

        // Extract session suffix (FN / AN / EN)
        final parts = colName.split('_');
        if (parts.length >= 3) {
          final session = parts.last; // 'FN', 'AN', or 'EN'
          sessionToColIndexes.putIfAbsent(session, () => []).add(j);
        }
      }

      if (sessionToColIndexes.isEmpty) {
        print(
          ' [ExamDetails] getCenterActiveExams: no exam columns for $today in sheet',
        );
        return [];
      }

      print(
        ' [ExamDetails] getCenterActiveExams: found exam sessions in CSV for today: ${sessionToColIndexes.keys.toList()}',
      );

      // Collect course codes for THIS centre, per session
      final Map<String, Set<String>> sessionToCourses = {};
      for (int i = 1; i < sheet.length; i++) {
        final row = sheet[i];
        if (row.length <= centreCol) continue;

        final rowCentre = row[centreCol]?.toString().trim() ?? '';
        if (rowCentre.toLowerCase() != centre.trim().toLowerCase()) continue;

        // Row belongs to this centre — collect course codes per session
        for (final entry in sessionToColIndexes.entries) {
          final session = entry.key;
          for (final colIdx in entry.value) {
            if (row.length <= colIdx) continue;
            final course = row[colIdx]?.toString().trim() ?? '';
            if (course.isNotEmpty && course.toUpperCase() != 'N/A') {
              sessionToCourses.putIfAbsent(session, () => {}).add(course);
            }
          }
        }
      }

      if (sessionToCourses.isEmpty) {
        print(
          ' [ExamDetails] getCenterActiveExams: no students from "$centre" found for today\'s sessions',
        );
        return [];
      }

      print(
        ' [ExamDetails] getCenterActiveExams: sessions with students in "$centre": ${sessionToCourses.keys.toList()}',
      );

      // ── Step 2 & 3: DynamoDB timings + time check ─────────────────────────
      final dbService = DynamoDBService();
      final timingData = await dbService.getCenterTimings(centre);

      if (timingData['success'] != true) {
        print(
          ' [ExamDetails] getCenterActiveExams: no DynamoDB timings for "$centre" — skipping time filter',
        );
        // No timings: cannot verify if session is active, skip S3 check
        return [];
      }

      final Map<String, String> timings = timingData['data'];
      final currentTimeStr = DateFormat('HH:mm:ss').format(DateTime.now());

      final List<Map<String, dynamic>> activeExams = [];

      for (final sessionEntry in sessionToCourses.entries) {
        final session = sessionEntry.key; // e.g. 'FN'
        final courses = sessionEntry.value; // e.g. {'DUMMZA110-EC3R'}

        final rawStart = timings['${session}_start'] ?? '';
        final rawEnd = timings['${session}_end'] ?? '';

        if (rawStart.isEmpty || rawEnd.isEmpty) {
          print(
            ' [ExamDetails] getCenterActiveExams: no timings for session $session — skipping',
          );
          continue;
        }

        final normStart = _normalizeTime(rawStart);
        final normEnd = _normalizeTime(rawEnd);

        final isActive =
            currentTimeStr.compareTo(normStart) >= 0 &&
            currentTimeStr.compareTo(normEnd) <= 0;

        print(
          ' [ExamDetails] Session $session: $normStart – $normEnd | now=$currentTimeStr | active=$isActive',
        );

        if (!isActive) continue;

        // Session is live — add one entry per course code
        if (courses.isEmpty) {
          // Centre has students in this session but no course code filled in
          activeExams.add({
            'courseCode': '',
            'examStartTime': normStart,
            'examEndTime': normEnd,
            'session': session,
          });
        } else {
          for (final course in courses) {
            activeExams.add({
              'courseCode': course,
              'examStartTime': normStart,
              'examEndTime': normEnd,
              'session': session,
            });
          }
        }
      }

      if (activeExams.isEmpty) {
        print(
          ' [ExamDetails] getCenterActiveExams: no session is currently active for "$centre"',
        );
      } else {
        print(
          ' [ExamDetails] getCenterActiveExams: ${activeExams.length} active exam(s) for "$centre": $activeExams',
        );
      }

      return activeExams;
    } catch (e) {
      print(' [ExamDetails] getCenterActiveExams error: $e');
      return [];
    }
  }

  static String _normalizeTime(String time) {
    time = time.trim().toUpperCase();
    if (time.isEmpty) return '';

    // Handle hh:mm a format
    if (time.contains('AM') || time.contains('PM')) {
      try {
        final format = time.contains(':')
            ? DateFormat('hh:mm a')
            : DateFormat('h a');
        final dt = format.parse(time);
        return DateFormat('HH:mm:ss').format(dt);
      } catch (e) {
        debugPrint('[ExamDetailsService] Time normalization fallback for "$time": $e');
      }
    }

    // Handle HH:mm or HH:mm:ss
    final parts = time.split(':');
    if (parts.length >= 2) {
      final h = parts[0].padLeft(2, '0');
      final m = parts[1].padLeft(2, '0');
      final s = parts.length > 2 ? parts[2].padLeft(2, '0') : '00';
      return '$h:$m:$s';
    }
    return time;
  }

  static int? _findColumnIndex(List<dynamic> header, List<String> targets) {
    for (int i = 0; i < header.length; i++) {
      final val = header[i]?.toString().trim().toUpperCase() ?? '';
      if (targets.contains(val)) return i;
    }
    return null;
  }

  /// Returns lowercase BITS IDs of ALL students registered in [centre].
  /// No exam-column filter — the S3 path check handles date+course filtering.
  /// Uses the cached student sheet — no extra network calls.
  static Future<List<String>> getStudentIdsInCentreForActiveExam(
    String centre,
    List<Map<String, dynamic>> activeExams,
  ) async {
    if (activeExams.isEmpty) return [];
    try {
      final sheet = await _getAndParseStudentSheet();
      if (sheet.isEmpty) return [];

      final header = sheet[0];
      final bitsIdCol = _findColumnIndex(header, ['BITS ID', 'BITSID']);
      final centreCol = _findColumnIndex(header, [
        'CENTRE',
        'CENTER',
        'EXAM HALL',
      ]);
      if (bitsIdCol == null || centreCol == null) {
        print(' [ExamDetails] BITS ID or CENTRE column not found');
        return [];
      }

      // Get ALL students in this centre
      // (S3 path with today's date + course code is the real filter)
      final List<String> ids = [];
      for (int i = 1; i < sheet.length; i++) {
        final row = sheet[i];
        if (row.length <= centreCol) continue;
        final rowCentre = row[centreCol]?.toString().trim() ?? '';
        if (rowCentre.toLowerCase() != centre.trim().toLowerCase()) continue;

        final id = row.length > bitsIdCol
            ? row[bitsIdCol]?.toString().trim() ?? ''
            : '';
        if (id.isNotEmpty) ids.add(id.toLowerCase());
      }

      print(' [ExamDetails] Found ${ids.length} student(s) in "$centre": $ids');
      return ids;
    } catch (e) {
      print(' [ExamDetails] Error in getStudentIdsInCentreForActiveExam: $e');
      return [];
    }
  }

  /// Step 3 — Get ALL exams for today (regardless of current time)
  static Future<List<Map<String, dynamic>>> getCenterExamsForToday(
    String centre,
  ) async {
    try {
      final sheet = await _getAndParseStudentSheet();
      if (sheet.isEmpty) return [];

      final header = sheet[0];
      final centreCol = _findColumnIndex(header, [
        'CENTER',
        'CENTRE',
        'EXAM HALL',
      ]);
      final bitsIdCol = _findColumnIndex(header, ['BITS ID', 'BITSID']);

      if (centreCol == null || bitsIdCol == null) return [];

      final today = DateFormat('dd-MM-yyyy').format(DateTime.now());
      final Map<String, List<int>> sessionToColIndexes = {};
      for (int j = 0; j < header.length; j++) {
        final colName = header[j]?.toString().trim().toUpperCase() ?? '';
        if (!colName.contains(today.toUpperCase())) continue;
        final parts = colName.split('_');
        if (parts.length >= 3) {
          final session = parts.last;
          sessionToColIndexes.putIfAbsent(session, () => []).add(j);
        }
      }

      if (sessionToColIndexes.isEmpty) return [];

      final Map<String, Set<String>> sessionToCourses = {};
      for (int i = 1; i < sheet.length; i++) {
        final row = sheet[i];
        if (row.length <= centreCol) continue;
        if (row[centreCol]?.toString().trim().toLowerCase() !=
            centre.trim().toLowerCase())
          continue;

        for (final entry in sessionToColIndexes.entries) {
          final session = entry.key;
          for (final colIdx in entry.value) {
            if (row.length <= colIdx) continue;
            final course = row[colIdx]?.toString().trim() ?? '';
            if (course.isNotEmpty && course.toUpperCase() != 'N/A') {
              sessionToCourses.putIfAbsent(session, () => {}).add(course);
            }
          }
        }
      }

      if (sessionToCourses.isEmpty) return [];

      final dbService = DynamoDBService();
      final timingData = await dbService.getCenterTimings(centre);
      final Map<String, String> timings = timingData['success'] == true
          ? timingData['data']
          : {};

      final List<Map<String, dynamic>> exams = [];
      for (final sessionEntry in sessionToCourses.entries) {
        final session = sessionEntry.key;
        final courses = sessionEntry.value;

        final rawStart = timings['${session}_start'] ?? '';
        final rawEnd = timings['${session}_end'] ?? '';
        final normStart = rawStart.isNotEmpty
            ? _normalizeTime(rawStart)
            : '00:00:00';
        final normEnd = rawEnd.isNotEmpty ? _normalizeTime(rawEnd) : '23:59:59';

        for (final courseCode in courses) {
          exams.add({
            'courseCode': courseCode,
            'examStartTime': normStart,
            'examEndTime': normEnd,
            'session': session,
          });
        }
      }

      return exams;
    } catch (e) {
      print(' [ExamDetails] Error in getCenterExamsForToday: $e');
      return [];
    }
  }
}
