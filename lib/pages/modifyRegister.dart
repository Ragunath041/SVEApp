// ignore_for_file: deprecated_member_use, avoid_print, file_names

import 'package:flutter/material.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:supervisorapp/Services/StorageService.dart';
import 'package:supervisorapp/Services/auth/supervisor_auth_service.dart';
import 'package:supervisorapp/constants/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ModifyRegister extends StatefulWidget {
  final String supervisorId;
  final String fullName;
  final String currentCentre;
  final String currentInvigilatorType;

  const ModifyRegister({
    super.key,
    required this.supervisorId,
    required this.fullName,
    required this.currentCentre,
    required this.currentInvigilatorType,
  });

  @override
  State<ModifyRegister> createState() => _ModifyRegisterState();
}

class _ModifyRegisterState extends State<ModifyRegister> {
  String? selectedCentre;
  String? selectedInvigilatorType;
  final StorageService _storageService = StorageService();
  final DynamoDBService _dynamoDBService = DynamoDBService();
  bool _isUpdating = false;

  // Dynamic centres loaded from DynamoDB bits-exam-centers
  List<String> _examCentres = [];
  bool _loadingCentres = true;
  String? _centresError;

  static const String _centresCacheKey = 'cached_exam_centres';

  @override
  void initState() {
    super.initState();
    // Invigilator type — still uses constants (rarely changes)
    if (AppConstants.invigilatorTypes.contains(widget.currentInvigilatorType)) {
      selectedInvigilatorType = widget.currentInvigilatorType;
    } else {
      selectedInvigilatorType = null;
    }
    _loadExamCentres();
  }

  /// Loads centres from DynamoDB, falls back to SharedPreferences cache if offline.
  Future<void> _loadExamCentres() async {
    setState(() {
      _loadingCentres = true;
      _centresError = null;
    });

    try {
      final result = await _dynamoDBService.getAllExamCentres();

      if (result['success'] == true) {
        final centres = List<String>.from(result['centres'] ?? []);

        // Persist to cache for offline use
        final prefs = SharedPreferencesAsync();
        await prefs.setString(_centresCacheKey, jsonEncode(centres));
        print(
          '[ModifyRegister] Loaded ${centres.length} centres from DynamoDB',
        );

        if (mounted) {
          setState(() {
            _examCentres = centres;
            // Auto-select current centre if it exists in the list
            selectedCentre = centres.contains(widget.currentCentre)
                ? widget.currentCentre
                : null;
            _loadingCentres = false;
          });
        }
      } else {
        // Network failed — try the local cache
        await _loadCentresFromCache();
      }
    } catch (e) {
      print('[ModifyRegister] DynamoDB error: $e');
      await _loadCentresFromCache();
    }
  }

  /// Loads centres from SharedPreferences cache when offline.
  Future<void> _loadCentresFromCache() async {
    try {
      final prefs = SharedPreferencesAsync();
      final cached = await prefs.getString(_centresCacheKey);
      if (cached != null) {
        final centres = List<String>.from(jsonDecode(cached));
        print(
          '[ModifyRegister] Using cached centres (${centres.length} items)',
        );
        if (mounted) {
          setState(() {
            _examCentres = centres;
            selectedCentre = centres.contains(widget.currentCentre)
                ? widget.currentCentre
                : null;
            _loadingCentres = false;
            _centresError = null;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('ModifyRegister: Error loading centres from cache: $e');
    }

    // Nothing in cache either
    if (mounted) {
      setState(() {
        _loadingCentres = false;
        _centresError = 'Could not load centres. Please check your connection.';
      });
    }
  }

  @override
  void dispose() {
    _storageService.dispose();
    _dynamoDBService.dispose();
    super.dispose();
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Update Failed'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showSuccessDialog() {
    final navigator = Navigator.of(context); // Capture the screen's navigator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Success'),
          content: const Text('Registration details updated successfully!'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(); // Close dialog using its own context
                navigator.pop(
                  true,
                ); // Return to homepage using captured navigator
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleSaveChanges() async {
    if (selectedCentre == null || selectedInvigilatorType == null) {
      _showErrorDialog('Please select both Centre and Invigilator Type.');
      return;
    }

    // Check if anything changed
    if (selectedCentre == widget.currentCentre &&
        selectedInvigilatorType == widget.currentInvigilatorType) {
      _showErrorDialog('No changes detected.');
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      // 1. Update DynamoDB
      final dynamoResult = await _dynamoDBService.updateSupervisor(
        supervisorId: widget.supervisorId,
        centre: selectedCentre!,
        invigilatorType: selectedInvigilatorType!,
      );

      if (!dynamoResult['success']) {
        setState(() {
          _isUpdating = false;
        });
        _showErrorDialog(
          dynamoResult['error'] ??
              'Unable to update profile. Please try again.',
        );
        debugPrint('DynamoDB Update Failed: ${dynamoResult['error']}');
        return;
      }

      // 2. Update Local Storage and S3
      final storageResult = await _storageService.updateSupervisorData(
        supervisorId: widget.supervisorId,
        centre: selectedCentre!,
        invigilatorType: selectedInvigilatorType!,
      );

      setState(() {
        _isUpdating = false;
      });

      if (!storageResult['success']) {
        _showErrorDialog(
          storageResult['error'] ??
              'Unable to save profile changes. Please try again.',
        );
        debugPrint('Storage Update Failed: ${storageResult['error']}');
        return;
      }

      // All updates successful
      _showSuccessDialog();
    } catch (e) {
      setState(() {
        _isUpdating = false;
      });
      _showErrorDialog(
        'An error occurred while updating your profile. Please try again.',
      );
      debugPrint('Error: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
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
                'Supervisor Manager',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 10),

              Align(
                alignment: Alignment.center,
                child: Text(
                  "Modify Registration Details",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),

              SizedBox(height: 30),

              // Name Field (Read-only)
              Text(
                "Name",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.fullName,
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
              ),

              SizedBox(height: 20),

              // Supervisor ID Field (Read-only)
              Text(
                "Supervisor ID",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.supervisorId,
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
              ),

              SizedBox(height: 20),

              // Present Centre Dropdown
              Text(
                "Present Centre",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 8),
              if (_loadingCentres)
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF444CE7),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Loading centres...',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              else if (_centresError != null)
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _centresError!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadExamCentres,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: selectedCentre,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
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
                      vertical: 14,
                    ),
                  ),
                  hint: Text(
                    "Select Present Centre",
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  items: _examCentres
                      .map(
                        (centre) => DropdownMenuItem(
                          value: centre,
                          child: SizedBox(
                            width: 280,
                            child: Text(
                              centre,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedCentre = value;
                    });
                  },
                ),

              SizedBox(height: 20),

              // Invigilator Type Dropdown
              Text(
                "Invigilator Type",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedInvigilatorType,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
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
                    vertical: 14,
                  ),
                ),
                hint: Text(
                  "Select Invigilator Type",
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                items: AppConstants.invigilatorTypes
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type)),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedInvigilatorType = value;
                  });
                },
              ),

              SizedBox(height: 30),

              // Save Changes Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isUpdating ? null : _handleSaveChanges,
                  icon: _isUpdating
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(Icons.save, size: 20),
                  label: Text(
                    _isUpdating ? "Updating..." : "Save Changes",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color.fromARGB(255, 68, 76, 231),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppFooter(),
    );
  }
}
