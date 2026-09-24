import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_settings/app_settings.dart';

class AWSClockSyncService {
  static const String _prefKeyDialogShown = 'aws_clock_sync_dialog_shown';

  /// Detects likely time-related AWS Signature V4 failures based on error messages
  static bool isLikelyDeviceTimeIssue(Object error, [String? responseBody]) {
    final String errorText = '$error ${responseBody ?? ''}'.toLowerCase();

    final List<String> targetPhrases = [
      'signature expired',
      'requesttimetooskewed',
      'request timestamp expired',
      'clock skew',
      'signature expired:',
    ];

    for (final phrase in targetPhrases) {
      if (errorText.contains(phrase)) {
        return true;
      }
    }

    return false;
  }

  /// Opens the Date & Time settings page on the device
  static Future<void> openDateTimeSettings() async {
    try {
      // Open the Date & Time settings directly
      await AppSettings.openAppSettings(type: AppSettingsType.date);
    } catch (e) {
      debugPrint('Failed to open Date settings directly: $e');
      try {
        await AppSettings.openAppSettings();
      } catch (fallbackError) {
        debugPrint('Failed to open fallback settings: $fallbackError');
      }
    }
  }

  /// Shows the alert dialog guiding the user to enable automatic time settings
  static Future<void> showAutoTimeDialogIfNeeded(
    BuildContext context, {
    String? errorMessage,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // TEMPORARILY DISABLED for testing:
    // final bool alreadyShown = prefs.getBool(_prefKeyDialogShown) ?? false;
    // if (alreadyShown) {
    //   debugPrint('Auto time sync dialog was already shown. Skipping.');
    //   return;
    // }

    if (!context.mounted) return;

    final isAndroid = Platform.isAndroid;
    final title = 'Enable Automatic Date & Time';

    final message = isAndroid
        ? 'Your phone time appears to be incorrect. Please enable Automatic Date & Time so secure network requests can work properly.\n\nInstructions:\n1. Tap "Open Settings"\n2. Search for "Date & time" in your settings\n3. Turn on the option for "Automatic date & time" or "Network-provided time"'
        : 'Your iPhone time appears to be incorrect. Please enable "Set Automatically" in Date & Time settings so secure network requests can work properly.\n\nInstructions:\n1. Tap "Open Settings"\n2. Go to General -> Date & Time\n3. Turn on "Set Automatically"';

    await showDialog(
      context: context,
      barrierDismissible: false, // Must be forced to resolve
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.schedule, color: Colors.amber, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text(
                'Not now',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await openDateTimeSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );

    // Save the flag so the dialog is only shown once per installation
    await prefs.setBool(_prefKeyDialogShown, true);
  }

  /// Single entry point to handle possible clock sync/time issues
  static Future<void> handlePossibleTimeIssue(
    BuildContext context,
    Object error, {
    String? responseBody,
  }) async {
    if (isLikelyDeviceTimeIssue(error, responseBody)) {
      await showAutoTimeDialogIfNeeded(context, errorMessage: error.toString());
    }
  }

  /// Reset function to re-enable showing the dialog (for testing purposes)
  static Future<void> resetAutoTimeDialogFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyDialogShown);
    debugPrint('Reset Auto Time Dialog Shown Flag.');
  }
}
