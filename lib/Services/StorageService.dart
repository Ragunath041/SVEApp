import 'storage/session_cache_service.dart';
import 'storage/supervisor_storage_service.dart';
import 'storage/answer_sheet_upload_service.dart';
import 'storage/incident_upload_service.dart';
import 'storage/attendance_sheet_service.dart';

/// Facade for storage operations, delegating to specialized modular sub-services:
/// - [SessionCacheService]: Local session state, SharedPreferences, window detection.
/// - [SupervisorStorageService]: Cloud sync for supervisor profile and face photos.
/// - [AnswerSheetUploadService]: Student answer sheets PDF generation & S3 upload.
/// - [IncidentUploadService]: Malpractice report PDF generation & S3 upload.
/// - [AttendanceSheetService]: Physical attendance sheet scans upload.
class StorageService {
  StorageService();

  /// Save registration data to local storage
  Future<bool> saveToLocalStorage({
    required String supervisorId,
    required String fullName,
    required String email,
    required String centre,
    required String invigilatorType,
    required String phoneNumber,
    required String city,
    required String address,
    String? imagePath,
    Map<String, String>? imagePaths,
  }) =>
      SessionCacheService.saveToLocalStorage(
        supervisorId: supervisorId,
        fullName: fullName,
        email: email,
        centre: centre,
        invigilatorType: invigilatorType,
        phoneNumber: phoneNumber,
        city: city,
        address: address,
        imagePath: imagePath,
        imagePaths: imagePaths,
      );

  /// Upload face image to S3 bucket
  Future<Map<String, dynamic>> uploadFaceImage({
    required String imagePath,
    required String supervisorId,
    String suffix = 'face.jpg',
  }) =>
      SupervisorStorageService.uploadFaceImage(
        imagePath: imagePath,
        supervisorId: supervisorId,
        suffix: suffix,
      );

  /// Upload registration data as JSON to S3
  Future<Map<String, dynamic>> uploadRegistrationData({
    required String supervisorId,
    required String fullName,
    required String email,
    required String centre,
    required String invigilatorType,
    required String phoneNumber,
    required String city,
    required String address,
    String? imageUrl,
    Map<String, String>? imageUrls,
  }) =>
      SupervisorStorageService.uploadRegistrationData(
        supervisorId: supervisorId,
        fullName: fullName,
        email: email,
        centre: centre,
        invigilatorType: invigilatorType,
        phoneNumber: phoneNumber,
        city: city,
        address: address,
        imageUrl: imageUrl,
        imageUrls: imageUrls,
      );

  /// Complete registration: Upload images, upload JSON, and save locally
  Future<Map<String, dynamic>> completeRegistration({
    required String supervisorId,
    required String fullName,
    required String email,
    required String centre,
    required String invigilatorType,
    required String phoneNumber,
    required String city,
    required String address,
    String? imagePath,
    Map<String, String>? imagePaths,
  }) =>
      SupervisorStorageService.completeRegistration(
        supervisorId: supervisorId,
        fullName: fullName,
        email: email,
        centre: centre,
        invigilatorType: invigilatorType,
        phoneNumber: phoneNumber,
        city: city,
        address: address,
        imagePath: imagePath,
        imagePaths: imagePaths,
      );

  /// Get registration data from local storage
  Future<Map<String, dynamic>?> getLocalRegistrationData(String supervisorId) =>
      SessionCacheService.getLocalRegistrationData(supervisorId);

  /// Download registration data from S3 and sync to local storage
  Future<Map<String, dynamic>> downloadRegistrationFromCloud({
    required String supervisorId,
  }) =>
      SupervisorStorageService.downloadRegistrationFromS3(
        supervisorId: supervisorId,
      );

  /// Alias for downloadRegistrationFromCloud
  Future<Map<String, dynamic>> downloadRegistrationFromS3({
    required String supervisorId,
  }) =>
      SupervisorStorageService.downloadRegistrationFromS3(
        supervisorId: supervisorId,
      );

  /// Update supervisor data in local storage and S3
  Future<Map<String, dynamic>> updateSupervisorData({
    required String supervisorId,
    required String centre,
    required String invigilatorType,
  }) =>
      SupervisorStorageService.updateSupervisorData(
        supervisorId: supervisorId,
        centre: centre,
        invigilatorType: invigilatorType,
      );

  /// Upload student answer sheets as A4 PDFs to S3
  Future<Map<String, dynamic>> uploadAnswerSheets({
    required String studentId,
    String? studentName,
    required String courseCode,
    required Map<String, List<String>> capturedImages,
  }) =>
      AnswerSheetUploadService.uploadAnswerSheets(
        studentId: studentId,
        studentName: studentName,
        courseCode: courseCode,
        capturedImages: capturedImages,
      );

  /// Upload Incident Report (JSON, Evidence Photos, and PDF Summary) to S3
  Future<Map<String, dynamic>> uploadIncidentReport({
    required Map<String, dynamic> formData,
    required List<String> photosPaths,
  }) =>
      IncidentUploadService.uploadIncidentReport(
        formData: formData,
        photosPaths: photosPaths,
      );

  /// Upload physical attendance sheet images to S3
  Future<Map<String, dynamic>> uploadAttendanceSheetImages({
    required List<String> imagePaths,
    required String date,
    required String session,
    required String centre,
  }) =>
      AttendanceSheetService.uploadAttendanceSheetImages(
        imagePaths: imagePaths,
        date: date,
        session: session,
        centre: centre,
      );

  /// Helper to calculate current active exam session from cached timings
  Future<Map<String, dynamic>?> getCurrentActiveExam(String centreName) =>
      SessionCacheService.getCurrentActiveExam(centreName);

  /// Mark a session as completed locally
  Future<void> markSessionAsFinished(
    String supervisorId,
    String date,
    String session,
  ) =>
      SessionCacheService.markSessionAsFinished(supervisorId, date, session);

  /// Check if a session is already marked as logged in
  Future<bool> isSessionMarked(
    String supervisorId,
    String date,
    String session,
  ) =>
      SessionCacheService.isSessionMarked(supervisorId, date, session);

  /// Explicitly save the current session window
  Future<void> saveCurrentSessionWindow({
    required String startTime,
    required String endTime,
  }) =>
      SessionCacheService.saveCurrentSessionWindow(
        startTime: startTime,
        endTime: endTime,
      );

  /// Clear the explicit session window (on logout)
  Future<void> clearCurrentSessionWindow() =>
      SessionCacheService.clearCurrentSessionWindow();

  /// Clear all local registration data
  Future<bool> clearAllRegistrationData() =>
      SessionCacheService.clearAllRegistrationData();

  /// Close any resources (stateless)
  void dispose() {}
}
