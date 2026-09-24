import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

class CourseNameService {
  static const String lambdaUrl = AppConfig.legacyExamLambdaUrl;

  /// Fetches course name for a given course code from S3 Excel
  /// Excel path: s3://bitsexamapp/exam_details/ExamDetails.xlsx
  static Future<Map<String, dynamic>> getCourseName(String fullCourseCode) async {
    try {
      final cleanCode = fullCourseCode.trim();
      final noSpaces = cleanCode.replaceAll(' ', '');
      final firstPartNoSpaces = cleanCode.split('-').first.replaceAll(' ', '');
      final firstPartAsIs = cleanCode.split('-').first.trim();

      // Collect unique variants to query sequentially
      final List<String> variants = [
        noSpaces,
        cleanCode,
        firstPartNoSpaces,
        firstPartAsIs,
      ].toSet().toList();

      print(' Fetching course name with variants: $variants');

      for (var code in variants) {
        try {
          print(' Querying variant: $code');
          final response = await http.get(
            Uri.parse('$lambdaUrl?courseCode=$code'),
          );

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['success'] == true) {
              print(' Course name found for variant $code: $data');
              return data;
            }
          }
        } catch (e) {
          print(' Error querying variant $code: $e');
        }
      }

      return {
        'success': false,
        'error': 'Unable to load course name. Please try again.',
      };
    } catch (e) {
      print(' Error fetching course name: $e');
      return {'success': false, 'error': 'Failed to load course information.'};
    }
  }
}
