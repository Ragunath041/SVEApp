import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

class CourseNameService {
  static final String lambdaUrl = AppConfig.mainBackendUrl;

  /// Fetches course name for a given course code via POST action (courseNameLookup).
  /// Tries multiple normalized variants to handle spacing differences.
  static Future<Map<String, dynamic>> getCourseName(
    String fullCourseCode,
  ) async {
    try {
      final cleanCode = fullCourseCode.trim();
      final noSpaces = cleanCode.replaceAll(' ', '');
      final firstPartNoSpaces = cleanCode.split('-').first.replaceAll(' ', '');
      final firstPartAsIs = cleanCode.split('-').first.trim();

      // Unique variants to try sequentially (most specific first)
      final variants = <String>{
        cleanCode,
        noSpaces,
        firstPartNoSpaces,
        firstPartAsIs,
      };

      debugPrint(
        ' [CourseNameService] Fetching course name with variants: $variants',
      );

      for (final code in variants) {
        try {
          debugPrint(' [CourseNameService] Querying variant: $code');
          final response = await http.post(
            Uri.parse(lambdaUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'courseNameLookup',
              'courseCode': code,
            }),
          );

          if (response.statusCode == 200) {
            final data = json.decode(response.body) as Map<String, dynamic>;
            if (data['success'] == true &&
                data.containsKey('courseName') &&
                (data['courseName'] as String).isNotEmpty) {
              debugPrint(
                ' [CourseNameService] Found for "$code": ${data['courseName']}',
              );
              return data;
            }
          }
        } catch (e) {
          debugPrint(' [CourseNameService] Error querying variant $code: $e');
        }
      }

      return {
        'success': false,
        'error': 'Course name not found for "$fullCourseCode".',
      };
    } catch (e) {
      debugPrint(' [CourseNameService] Error: $e');
      return {'success': false, 'error': 'Failed to load course information.'};
    }
  }
}
