// ignore_for_file: avoid_print, file_names

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

class ExcelService {
  // Lambda Function URL for getting student IDs
  static const String _lambdaFunctionUrl = AppConfig.legacyExamLambdaUrl;

  /// Load student IDs from Lambda for students who have exams TODAY
  /// This is much faster and doesn't freeze the UI!
  static Future<List<String>> loadStudentIdsFromS3({DateTime? examDate}) async {
    try {
      // Use provided date or default to today
      final targetDate = examDate ?? DateTime.now();
      final dateStr =
          '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

      print(' Loading student IDs for date: $dateStr');

      // Build URL with date parameter
      final url = Uri.parse(
        _lambdaFunctionUrl,
      ).replace(queryParameters: {'date': dateStr});

      print(' Calling Lambda: $url');

      // Call Lambda function
      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw TimeoutException('Backend request timed out.');
            },
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          final List<dynamic> studentIdsJson = data['studentIds'];
          final List<String> studentIds = studentIdsJson
              .map((id) => id.toString())
              .toList();

          print(' Loaded ${studentIds.length} student IDs for $dateStr');

          // Log filter info if available
          if (data.containsKey('filterDate')) {
            print(' Filter date: ${data['filterDate']}');
            print(' Total rows: ${data['totalRows']}');
            print(' Filtered rows: ${data['filteredRows']}');
          }

          return studentIds;
        } else {
          print(' Lambda returned error: ${data['error']}');
          return [];
        }
      } else {
        print(' Lambda request failed with status: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print(' Error loading student IDs from Lambda: $e');
      return [];
    }
  }

  // Add to lib/Services/ExcelService.dart

  static Future<Map<String, dynamic>> fetchCurrentSessionHistory(
    String centre,
  ) async {
    try {
      final url = Uri.parse(_lambdaFunctionUrl).replace(
        queryParameters: {'action': 'sessionHistory', 'centre': centre},
      );

      final response = await http.get(url).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {
        'success': false,
        'error':
            'Unable to fetch exam schedule (Server response: ${response.statusCode}). Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'error':
            'Unable to connect to exam service. Please check your network connection.',
      };
    }
  }

  /// Load ALL student IDs from Lambda (no date filter)
  static Future<List<String>> loadAllStudentIds() async {
    try {
      print(' Loading ALL student IDs from Lambda...');

      // Build URL with action=allStudents parameter
      final url = Uri.parse(
        _lambdaFunctionUrl,
      ).replace(queryParameters: {'action': 'allStudents'});

      print(' Calling Lambda (All IDs): $url');

      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 45), // Longer timeout for larger data
            onTimeout: () {
              throw TimeoutException('Backend request timed out.');
            },
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          final List<dynamic> studentIdsJson = data['studentIds'];
          final List<String> studentIds = studentIdsJson
              .map((id) => id.toString())
              .toList();

          print(' Loaded ${studentIds.length} total student IDs');
          return studentIds;
        } else {
          print(' Lambda returned error: ${data['error']}');
          return [];
        }
      } else {
        print(' Lambda request failed with status: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print(' Error loading ALL student IDs from Lambda: $e');
      return [];
    }
  }

  /// Fetch all exams happening at a specific center for a given date
  static Future<List<Map<String, String>>> fetchCenterExams({
    required String centre,
    DateTime? date,
  }) async {
    try {
      final targetDate = date ?? DateTime.now();
      final dateStr =
          '${targetDate.day.toString().padLeft(2, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.year}';

      print(' Fetching exams for center: $centre on $dateStr');

      final url = Uri.parse(_lambdaFunctionUrl).replace(
        queryParameters: {
          'action': 'centerExams',
          'centre': centre,
          'date': dateStr,
        },
      );

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> examsJson = data['exams'];
          return examsJson.map((e) {
            return {
              'courseCode': e['courseCode'].toString(),
              'session': e['session'].toString(),
            };
          }).toList();
        }
      }
      return [];
    } catch (e) {
      print(' Error fetching center exams: $e');
      return [];
    }
  }

  /// Fetch real-time attendance status for a specific exam
  static Future<Map<String, dynamic>> getAttendanceStatus({
    required String centre,
    required String courseCode,
    required String session,
    DateTime? date,
  }) async {
    try {
      final targetDate = date ?? DateTime.now();
      final dateStr =
          '${targetDate.day.toString().padLeft(2, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.year}';

      final url = Uri.parse(_lambdaFunctionUrl).replace(
        queryParameters: {
          'action': 'attendanceStatus',
          'centre': centre,
          'courseCode': courseCode,
          'session': session,
          'date': dateStr,
        },
      );

      print(' Fetching attendance status: $url');

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {
        'success': false,
        'error': 'Server error (${response.statusCode}). Please try again.',
      };
    } catch (e) {
      print(' Error getting attendance status: $e');
      return {
        'success': false,
        'error':
            'Failed to load attendance status. Please check your connection.',
      };
    }
  }
}
