import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supervisorapp/widgets/QRScannerPage.dart';
import '../core/config/app_config.dart';

class ExamDetailsLambdaService {
  static const String _lambdaUrl = AppConfig.legacyExamLambdaUrl;

  /// Fetch full exam details for a student from Lambda.
  /// Lambda merges BITS-exam.xlsx + ExamDetails.xlsx server-side.
  /// Returns same shape as ExamDetailsService.getStudentExamDetails()
  static Future<Map<String, dynamic>> getStudentExamDetails(
    String studentId,
  ) async {
    try {
      final url = Uri.parse(
        '$_lambdaUrl?studentId=${Uri.encodeComponent(studentId)}',
      );
      print(' Calling Lambda for student: $studentId → $url');

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print(' Lambda response: $data');
        return data;
      } else {
        print(' Lambda returned HTTP ${response.statusCode}: ${response.body}');
        return {
          'success': false,
          'error': 'Server error (${response.statusCode}). Please try again.',
        };
      }
    } catch (e) {
      print(' Lambda call failed: $e');
      return {
        'success': false,
        'error': 'Network error. Please check your connection.',
      };
    }
  }

  /// Save student QR code verification details to DynamoDB via Lambda.
  static Future<Map<String, dynamic>> saveScannedStudentData(
    ScannedStudentData data,
    String scannedTime,
    String scannedDate,
  ) async {
    try {
      final url = Uri.parse(_lambdaUrl);
      print(' Saving scanned student data to Lambda: ${data.bitsId} → $url');

      final body = json.encode({
        'action': 'saveScannedQR',
        'bitsId': data.bitsId,
        'name': data.name,
        'organization': data.organization,
        'center': data.center,
        'courseCode': data.courseCode,
        'courseName': data.courseName,
        'examDate': data.date,
        'examTiming': data.time,
        'scannedtime': scannedTime,
        'scanneddate': scannedDate,
        'supervisorId': data.supervisorId,
      });

      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final resData = json.decode(response.body);
        print(' Lambda save response: $resData');
        return resData;
      } else {
        print(' Lambda returned HTTP ${response.statusCode}: ${response.body}');
        return {
          'success': false,
          'error': 'Server error (${response.statusCode}). Please try again.',
        };
      }
    } catch (e) {
      print(' Lambda save call failed: $e');
      return {
        'success': false,
        'error': 'Network error. Please check your connection.',
      };
    }
  }
}
