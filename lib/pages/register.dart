import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supervisorapp/Services/FaceRecognitionService.dart';
import 'package:supervisorapp/pages/login.dart';
import 'package:supervisorapp/widgets/footer.dart';
import 'package:supervisorapp/Services/auth/supervisor_auth_service.dart';
import 'package:supervisorapp/Services/StorageService.dart';
import 'package:supervisorapp/pages/face_camera_page.dart';
import 'package:supervisorapp/pages/face_capture_guide_page.dart';
import 'package:supervisorapp/Services/AWSClockSyncService.dart';
import 'package:supervisorapp/Services/logging/supervisor_audit_log_service.dart';
import 'package:supervisorapp/constants/app_constants.dart';

class Register extends StatefulWidget {
  final String? fullName;
  final String? supervisorId;
  final String? email;
  final bool isFreshRegistration;

  const Register({
    super.key,
    this.fullName,
    this.supervisorId,
    this.email,
    this.isFreshRegistration = false,
  });

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  String? selectedCentre;
  String? selectedInvigilatorType;
  String photoStatus = "Capture 5 poses below";
  Map<String, String?> capturedImages = {
    'straight': null,
    'left': null,
    'right': null,
    'top': null,
    'down': null,
  };
  List<String> _poseEmbeddings = []; // Store embeddings for consensus

  final List<Map<String, String>> poses = [
    {'id': 'straight', 'label': 'Straight'},
    {'id': 'left', 'label': 'slightly Left'},
    {'id': 'right', 'label': 'slightly Right'},
    {'id': 'top', 'label': 'slightly Up'},
    {'id': 'down', 'label': 'slightly Down'},
  ];
  late TextEditingController fullNameController;
  late TextEditingController supervisorIdController;
  late TextEditingController emailController;
  late TextEditingController phoneNumberController;
  late TextEditingController cityController;
  late TextEditingController addressController;
  late TextEditingController centreController;
  late TextEditingController invigilatorTypeController;
  final DynamoDBService _dynamoDBService = DynamoDBService();
  final StorageService _storageService = StorageService();
  bool _isValidating = false;
  bool _isVerified = false; // Track if supervisor ID is verified
  bool _isVerifying = false; // Track verification in progress
  bool _showFaceRegisterView = false;
  int _currentPoseIndex = -1;
  List<String> _centresList = [];
  bool _isLoadingCentres = true;

  bool get _showFullName =>
      widget.isFreshRegistration ||
      (_isVerified && fullNameController.text.trim().isNotEmpty);
  bool get _showCentre =>
      widget.isFreshRegistration ||
      (_isVerified &&
          selectedCentre != null &&
          selectedCentre!.trim().isNotEmpty);
  bool get _showType =>
      widget.isFreshRegistration ||
      (_isVerified &&
          selectedInvigilatorType != null &&
          selectedInvigilatorType!.trim().isNotEmpty);
  bool get _showEmail =>
      widget.isFreshRegistration ||
      (_isVerified && emailController.text.trim().isNotEmpty);
  bool get _showPhone =>
      widget.isFreshRegistration ||
      (_isVerified && phoneNumberController.text.trim().isNotEmpty);
  bool get _showCity =>
      widget.isFreshRegistration ||
      (_isVerified && cityController.text.trim().isNotEmpty);
  bool get _showAddress =>
      widget.isFreshRegistration ||
      (_isVerified && addressController.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _fetchCentres();
    fullNameController = TextEditingController(text: widget.fullName);
    supervisorIdController = TextEditingController(text: widget.supervisorId);
    emailController = TextEditingController(text: widget.email);
    phoneNumberController = TextEditingController();
    cityController = TextEditingController();
    addressController = TextEditingController();
    centreController = TextEditingController();
    invigilatorTypeController = TextEditingController();
    if (widget.isFreshRegistration) {
      _isVerified = true;
    }
  }

  Future<void> _fetchCentres() async {
    final result = await _dynamoDBService.getAllExamCentres();
    if (mounted) {
      setState(() {
        if (result['success']) {
          _centresList = List<String>.from(result['centres']);
        }
        _isLoadingCentres = false;
      });
    }
  }

  @override
  void dispose() {
    fullNameController.dispose();
    supervisorIdController.dispose();
    emailController.dispose();
    phoneNumberController.dispose();
    cityController.dispose();
    addressController.dispose();
    centreController.dispose();
    invigilatorTypeController.dispose();
    _dynamoDBService.dispose();
    _storageService.dispose();
    super.dispose();
  }

  Future<void> _capturePose(Map<String, String> pose) async {
    final XFile? image = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceCameraPage(
          title: 'Step ${_currentPoseIndex + 1}/5 (${pose['label']})',
          instructionText: pose['id'] == 'straight'
              ? "Look Straight Ahead"
              : "Turn your head ${pose['label']}",
          supervisorId: supervisorIdController.text,
          autoCapture: true,
          poseId: pose['id']!,
        ),
      ),
    );

    if (image == null) {
      return;
    }

    _showLoadingDialog("Processing sample...");
    final embedding = await FaceRecognitionServiceEnhanced.generateEmbedding(
      image.path,
    );
    if (mounted) Navigator.pop(context); // Close loading

    if (embedding == null) {
      _showErrorDialog(
        "Could not find a clear face in that image. Please try again.",
      );
      return;
    }

    if (_poseEmbeddings.isNotEmpty) {
      // Consensus validation — threshold varies by pose because side/up/down
      // views are geometrically different from straight.
      final double threshold;
      switch (pose['id']) {
        case 'straight':
          threshold = 0.85;
          break;
        case 'left':
        case 'right':
        case 'top':
        case 'down':
          threshold = 0.70;
          break;
        default:
          threshold = 0.80;
      }

      final avgEmbedding = FaceRecognitionServiceEnhanced.aggregateEmbeddings(
        _poseEmbeddings,
      );
      final similarity = FaceRecognitionServiceEnhanced.compareFaces(
        avgEmbedding,
        embedding,
      );

      debugPrint(
        ' [Consensus] Pose="${pose['label']}" Similarity=${similarity.toStringAsFixed(3)} Threshold=$threshold',
      );

      if (similarity < threshold) {
        debugPrint(
          ' [Consensus] MISMATCH — ${similarity.toStringAsFixed(3)} < $threshold for pose "${pose['label']}".',
        );
        _showMismatchDialog(pose);
        return;
      }
    }

    // Success: Accept this sample
    _poseEmbeddings.add(embedding);
    setState(() {
      capturedImages[pose['id']!] = image.path;
      if (_currentPoseIndex < 4) {
        _currentPoseIndex++;
      } else {
        _currentPoseIndex = 5;
      }
    });

    if (_currentPoseIndex == 5) {
      await _completeRegistration();
    }
  }

  Widget _buildInlineCaptureCard() {
    final pose = poses[_currentPoseIndex];
    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Step ${_currentPoseIndex + 1} of 5",
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 0, 0, 0),
                ),
              ),
              Text(
                pose['id'] == 'straight'
                    ? "Look Straight Ahead"
                    : "Turn your head ${pose['label']}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color.fromARGB(255, 35, 106, 222),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => _capturePose(pose),
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  label: const Text(
                    "Start Capture",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color.fromARGB(255, 35, 106, 222),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Position your face and tap capture.",
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleVerifySupervisor() async {
    if (supervisorIdController.text.trim().isEmpty) {
      _showErrorDialog('Please enter your Supervisor ID.');
      return;
    }

    setState(() => _isVerifying = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext loadingDialogContext) {
        return const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: Color.fromARGB(255, 68, 76, 231),
                  ),
                  SizedBox(height: 16),
                  Text('Verifying...'),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      final supervisorId = supervisorIdController.text.trim();
      final downloadResult = await _storageService.downloadRegistrationFromS3(
        supervisorId: supervisorId,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (downloadResult['success']) {
        setState(() => _isVerifying = false);

        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext alreadyRegDialogContext) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 60,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Already Registered',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your registration profile is already active on this device. Tap Continue to proceed to login.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(alreadyRegDialogContext).pop();
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const Login(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(
                            255,
                            68,
                            76,
                            231,
                          ),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      } else {
        final detailsResult = await _dynamoDBService.getSupervisorDetails(
          supervisorId,
        );

        if (!mounted) return;

        if (detailsResult['success']) {
          final data = detailsResult['data'] ?? {};
          debugPrint('Fetched supervisor data: $data');

          setState(() {
            _isVerifying = false;
            _isVerified = true;

            fullNameController.text = data['name'] ?? data['Name'] ?? '';
            selectedCentre = data['centre'] ?? data['Exam hall'];
            selectedInvigilatorType = data['type'] ?? data['Type'];
            phoneNumberController.text = data['phoneNumber'] ?? '';
            cityController.text = data['city'] ?? '';
            addressController.text = data['address'] ?? '';
          });

          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext successDialogContext) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.withOpacity(0.1),
                        ),
                        child: const Icon(
                          Icons.verified_user,
                          color: Colors.green,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Supervisor ID Verified',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your Supervisor ID has been verified. Please proceed to complete face capture.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(successDialogContext).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromARGB(
                              255,
                              68,
                              76,
                              231,
                            ),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Proceed to Register',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
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
        } else {
          setState(() => _isVerifying = false);
          final String errorMsg =
              detailsResult['error'] ??
              'Supervisor ID not found, Please contact Admin';
          if (!mounted) return;
          if (AWSClockSyncService.isLikelyDeviceTimeIssue(errorMsg)) {
            AWSClockSyncService.handlePossibleTimeIssue(context, errorMsg);
          } else {
            _showErrorDialog(
              errorMsg,
              buttonText: errorMsg.toLowerCase().contains('not found')
                  ? 'Start Fresh Registration'
                  : null,
              onPressed: errorMsg.toLowerCase().contains('not found')
                  ? () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => Register(
                            isFreshRegistration: true,
                            supervisorId: supervisorIdController.text.trim(),
                          ),
                        ),
                      );
                    }
                  : null,
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(() => _isVerifying = false);
      _showErrorDialog(
        'Supervisor verification failed. Please check your internet connection and try again.',
      );
      debugPrint('Verification failed: $e');
    }
  }

  Future<void> _completeRegistration() async {
    setState(() {
      _isValidating = true;
    });

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: Color.fromARGB(255, 68, 76, 231),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Registering...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final storageResult = await _storageService.completeRegistration(
        supervisorId: supervisorIdController.text.trim(),
        fullName: fullNameController.text.trim(),
        email: emailController.text.trim(),
        centre: widget.isFreshRegistration
            ? centreController.text.trim()
            : selectedCentre!,
        invigilatorType: widget.isFreshRegistration
            ? invigilatorTypeController.text.trim()
            : selectedInvigilatorType!,
        phoneNumber: phoneNumberController.text.trim(),
        city: cityController.text.trim(),
        address: addressController.text.trim(),
        imagePaths: capturedImages.map((k, v) => MapEntry(k, v!)),
      );

      if (!storageResult['success']) {
        if (mounted) Navigator.of(context).pop();
        setState(() => _isValidating = false);
        final String errorMsg = storageResult['error'];
        S3LogService.logRegistration(
          supervisorId: supervisorIdController.text.trim(),
          action: 'COMPLETE_REGISTRATION',
          details: 'S3 asset upload failed',
          status: 'FAILED',
          errorMessage: errorMsg,
        );
        if (mounted) {
          if (AWSClockSyncService.isLikelyDeviceTimeIssue(errorMsg)) {
            AWSClockSyncService.handlePossibleTimeIssue(context, errorMsg);
          } else {
            _showErrorDialog(errorMsg);
          }
        }
        return;
      }

      // Use Enhanced Face Recognition with ALL 5 images

      // Show processing dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Color.fromARGB(255, 68, 76, 231),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Processing face images...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Analyzing all 5 poses',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      int successfulPosesCount = 0;
      try {
        await FaceRecognitionServiceEnhanced.initialize();

        // Generate embeddings from ALL 5 poses
        final List<String> allEmbeddings = [];
        int processedCount = 0;

        for (final poseEntry in capturedImages.entries) {
          print(' Processing ${poseEntry.key} pose...');

          final embedding =
              await FaceRecognitionServiceEnhanced.generateEmbedding(
                poseEntry.value!,
              );

          if (embedding != null) {
            allEmbeddings.add(embedding);
            processedCount++;
            print(
              ' ${poseEntry.key} pose processed successfully ($processedCount/5)',
            );
          } else {
            print(
              ' ${poseEntry.key} pose failed - no face detected or poor quality',
            );
          }
        }

        // Close processing dialog
        if (mounted) Navigator.of(context).pop();

        // Require at least 3 valid embeddings for good aggregation
        if (allEmbeddings.length < 3) {
          if (mounted) Navigator.of(context).pop(); // Close registration dialog
          setState(() => _isValidating = false);
          S3LogService.logRegistration(
            supervisorId: supervisorIdController.text.trim(),
            action: 'COMPLETE_REGISTRATION',
            details:
                'Face processing failed: only $processedCount/5 poses detected',
            status: 'FAILED',
            errorMessage: 'Face quality too low',
          );
          _showErrorDialog(
            'Face Quality Issue\n\n'
            'Only $processedCount out of 5 poses had good quality faces.\n\n'
            'Please ensure:\n'
            '• Good lighting\n'
            '• Face clearly visible\n'
            '• Look at camera for each pose',
          );
          return;
        }

        successfulPosesCount = allEmbeddings.length;

        // Aggregate all embeddings into single template
        print(' Aggregating ${allEmbeddings.length} embeddings...');
        final aggregatedEmbedding =
            FaceRecognitionServiceEnhanced.aggregateEmbeddings(allEmbeddings);

        // Close the "Registering..." dialog before showing verification dialog
        if (mounted) Navigator.of(context).pop();

        // Show verification dialog using the aggregated embedding template
        final verificationResult = await _showFaceVerificationDialog(
          aggregatedEmbedding,
        );

        if (!verificationResult.isVerified) {
          setState(() => _isValidating = false);
          S3LogService.logRegistration(
            supervisorId: supervisorIdController.text.trim(),
            action: 'COMPLETE_REGISTRATION',
            details: 'Post-registration face verification failed',
            status: 'FAILED',
            errorMessage: verificationResult.message,
          );
          _showErrorDialog(
            verificationResult.message.isNotEmpty
                ? verificationResult.message
                : 'Verification failed. Please try registering again.',
          );
          return;
        }

        // Show loading dialog again while saving embedding
        if (mounted) {
          _showLoadingDialog("Saving face template...");
        }

        // Save the aggregated template
        await FaceRecognitionServiceEnhanced.saveEmbedding(
          supervisorIdController.text.trim(),
          aggregatedEmbedding,
        );

        print(
          ' Registration complete with ${allEmbeddings.length}/5 poses aggregated',
        );
      } catch (embeddingError) {
        if (mounted) Navigator.of(context).pop(); // Close processing dialog
        if (mounted) Navigator.of(context).pop(); // Close registration dialog
        setState(() => _isValidating = false);
        S3LogService.logRegistration(
          supervisorId: supervisorIdController.text.trim(),
          action: 'COMPLETE_REGISTRATION',
          details: 'Face recognition module exception',
          status: 'FAILED',
          errorMessage: embeddingError.toString(),
        );
        _showErrorDialog(
          'Could not process face images. Please ensure good lighting and try again.',
        );
        debugPrint('Face processing failed: $embeddingError');
        return;
      }

      if (mounted) Navigator.of(context).pop(); // Close saving dialog
      setState(() => _isValidating = false);

      S3LogService.logRegistration(
        supervisorId: supervisorIdController.text.trim(),
        action: 'COMPLETE_REGISTRATION',
        details:
            'Registration completed successfully with $successfulPosesCount/5 poses',
        status: 'SUCCESS',
      );

      // Update DynamoDB with latest details
      await _dynamoDBService.updateSupervisor(
        supervisorId: supervisorIdController.text.trim(),
        centre: widget.isFreshRegistration
            ? centreController.text.trim()
            : selectedCentre!,
        invigilatorType: widget.isFreshRegistration
            ? invigilatorTypeController.text.trim()
            : selectedInvigilatorType!,
        phoneNumber: phoneNumberController.text.trim(),
        city: cityController.text.trim(),
        address: addressController.text.trim(),
        name: widget.isFreshRegistration
            ? fullNameController.text.trim()
            : null,
        email: widget.isFreshRegistration ? emailController.text.trim() : null,
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              "Registration Successful",
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
            ),
            content: Text(
              "Your supervisor profile has been successfully registered. Please proceed to login.",
            ),

            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => Login()),
                ),
                child: Text("Go to Login"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      setState(() => _isValidating = false);
      S3LogService.logRegistration(
        supervisorId: supervisorIdController.text.trim(),
        action: 'COMPLETE_REGISTRATION',
        details: 'Registration crashed',
        status: 'FAILED',
        errorMessage: e.toString(),
      );
      _showErrorDialog(
        'Registration could not be completed. Please check your connection and try again.',
      );
      debugPrint('Error: $e');
    }
  }

  Future<VerificationResult> _showFaceVerificationDialog(
    String trainingTemplate,
  ) async {
    final result = await showDialog<VerificationResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FaceVerificationDialog(
        trainingTemplate: trainingTemplate,
        userName: fullNameController.text.trim(),
      ),
    );

    return result ??
        VerificationResult(
          isVerified: false,
          message: 'Verification cancelled by user',
          similarity: 0.0,
          maxAttemptsReached: false,
        );
  }

  /// Shows a face-mismatch dialog with a "Try Again" button that
  /// automatically re-opens the camera for the SAME pose.
  void _showMismatchDialog(Map<String, String> pose) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withOpacity(0.1),
                    border: Border.all(color: Colors.red, width: 2.5),
                  ),
                  child: const Icon(
                    Icons.face_retouching_off,
                    color: Colors.red,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                // Title
                const Text(
                  'Face Verification Mismatch',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                // Message
                Text(
                  'The face in the "${pose['label']}" photo does not match your reference photo.\n\nPlease ensure the photo is clearly taken in good lighting.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Try Again button — re-opens camera for the SAME pose
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(); // close dialog
                      _capturePose(pose); // retry same pose
                    },
                    icon: const Icon(Icons.camera_alt, color: Colors.white),
                    label: Text(
                      'Try Again (${pose['label']})',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 68, 76, 231),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Cancel — stays on same pose card without opening camera
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
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

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Show error dialog
  void _showErrorDialog(
    String message, {
    String? buttonText,
    VoidCallback? onPressed,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Error icon
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red, width: 3),
                  ),
                  child: Icon(Icons.error_outline, color: Colors.red, size: 40),
                ),
                SizedBox(height: 20),
                // Error message (no title)
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24),
                // OK/Custom button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        onPressed ??
                        () {
                          Navigator.of(context).pop();
                        },
                    child: Text(
                      buttonText ?? "Try Again",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
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
                'Supervisor Attendance Manager',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      backgroundColor: Color.fromARGB(
        255,
        255,
        254,
        254,
      ), // Light gray background
      body: SafeArea(
        child: _showFaceRegisterView
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 40.0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_currentPoseIndex == -1) ...[
                      Center(
                        child: Container(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: () async {
                              setState(() {
                                capturedImages = {
                                  'straight': null,
                                  'left': null,
                                  'right': null,
                                  'top': null,
                                  'down': null,
                                };
                                _poseEmbeddings.clear();
                              });

                              final firstPose = poses[0];
                              final XFile?
                              firstImage = await Navigator.push<XFile?>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FaceCaptureGuidePage(
                                    title: 'Face Registration Guide',
                                    nextPage: FaceCameraPage(
                                      title: 'Step 1/5 (${firstPose['label']})',
                                      instructionText:
                                          "Look ${firstPose['label']}",
                                      supervisorId: supervisorIdController.text,
                                      autoCapture: true,
                                      poseId: firstPose['id']!,
                                    ),
                                  ),
                                ),
                              );

                              if (firstImage == null) return;

                              _showLoadingDialog("Processing sample...");
                              final firstEmbedding =
                                  await FaceRecognitionServiceEnhanced.generateEmbedding(
                                    firstImage.path,
                                  );
                              if (context.mounted) Navigator.pop(context);

                              if (firstEmbedding == null) {
                                _showErrorDialog(
                                  "Could not find a clear face in that image. Please try again.",
                                );
                                return;
                              }

                              _poseEmbeddings.add(firstEmbedding);
                              setState(() {
                                capturedImages[firstPose['id']!] =
                                    firstImage.path;
                                _currentPoseIndex = 1;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              "Register Yourself",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 16.0,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFBBF7D0),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green[600],
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                "Welcome ${fullNameController.text}! Please register your face.",
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF166534),
                                ),
                                textAlign: TextAlign.justify,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_currentPoseIndex >= 0 && _currentPoseIndex < 5) ...[
                      const SizedBox(height: 30),
                      _buildInlineCaptureCard(),
                    ],
                  ],
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 600),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 10.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Register Title
                          Center(
                            child: Text(
                              "Register",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(height: 8),

                          // Supervisor ID (moved to top)
                          Text(
                            "Supervisor ID",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
                          TextField(
                            controller: supervisorIdController,
                            textCapitalization: TextCapitalization.none,
                            enabled: !_isVerified, // Disable after verification
                            decoration: InputDecoration(
                              hintText: "Enter your Supervisor ID",
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              filled: true,
                              fillColor: _isVerified
                                  ? Colors.grey.shade100
                                  : Colors.white,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.white),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Color.fromARGB(255, 68, 76, 231),
                                ),
                              ),
                              disabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                          ),
                          SizedBox(height: 12),

                          // Verify Button
                          if (!widget.isFreshRegistration)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isVerifying || _isVerified
                                    ? null
                                    : _handleVerifySupervisor,
                                child: _isVerifying
                                    ? SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        _isVerified ? "Verified ✓" : "Verify",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isVerified
                                      ? Colors.green
                                      : Color.fromARGB(255, 68, 76, 231),
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          if (!widget.isFreshRegistration) SizedBox(height: 16),

                          // Full Name
                          if (_showFullName) ...[
                            Text(
                              "Full Name",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 4),
                            TextField(
                              controller: fullNameController,
                              enabled: widget.isFreshRegistration
                                  ? true
                                  : false,
                              decoration: InputDecoration(
                                hintText: _isVerified
                                    ? "Enter name"
                                    : "Enter name",
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                ),
                                filled: true,
                                fillColor: widget.isFreshRegistration
                                    ? Colors.white
                                    : Colors.grey.shade100,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Color.fromARGB(255, 68, 76, 231),
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                            ),
                            SizedBox(height: 8),
                          ],

                          // Centre Dropdown
                          if (_showCentre) ...[
                            Text(
                              "Centre",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 4),
                            widget.isFreshRegistration
                                ? DropdownButtonFormField<String>(
                                    value: selectedCentre,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      hintText: _isLoadingCentres
                                          ? "Loading centres..."
                                          : "Select Centre",
                                      hintStyle: TextStyle(
                                        color: Colors.grey.shade400,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.white,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Color.fromARGB(
                                            255,
                                            68,
                                            76,
                                            231,
                                          ),
                                        ),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                    ),
                                    items: _centresList
                                        .map(
                                          (centre) => DropdownMenuItem(
                                            value: centre,
                                            child: Text(
                                              centre,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: _isLoadingCentres
                                        ? null
                                        : (value) {
                                            setState(() {
                                              selectedCentre = value;
                                              centreController.text =
                                                  value ?? '';
                                            });
                                          },
                                  )
                                : DropdownButtonFormField<String>(
                                    value: selectedCentre,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.white,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Color.fromARGB(
                                            255,
                                            68,
                                            76,
                                            231,
                                          ),
                                        ),
                                      ),
                                      disabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                    ),
                                    hint: Text(
                                      _isVerified
                                          ? "Loading centre..."
                                          : "Centre",
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                    items: selectedCentre == null
                                        ? []
                                        : [
                                            DropdownMenuItem(
                                              value: selectedCentre,
                                              child: Text(
                                                selectedCentre!,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                    onChanged: null,
                                  ),
                            SizedBox(height: 8),
                          ],

                          // Invigilator Type
                          if (_showType) ...[
                            Text(
                              "Invigilator Type",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 4),
                            widget.isFreshRegistration
                                ? DropdownButtonFormField<String>(
                                    value: selectedInvigilatorType,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      hintText: "Select Invigilator Type",
                                      hintStyle: TextStyle(
                                        color: Colors.grey.shade400,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.white,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Color.fromARGB(
                                            255,
                                            68,
                                            76,
                                            231,
                                          ),
                                        ),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                    ),
                                    items: AppConstants.invigilatorTypes
                                        .map(
                                          (type) => DropdownMenuItem(
                                            value: type,
                                            child: Text(type),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        selectedInvigilatorType = value;
                                        invigilatorTypeController.text =
                                            value ?? '';
                                      });
                                    },
                                  )
                                : DropdownButtonFormField<String>(
                                    value: selectedInvigilatorType,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.white,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Color.fromARGB(
                                            255,
                                            68,
                                            76,
                                            231,
                                          ),
                                        ),
                                      ),
                                      disabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                    ),
                                    hint: Text(
                                      _isVerified ? "Loading type..." : "Type",
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                    items: selectedInvigilatorType == null
                                        ? []
                                        : [
                                            DropdownMenuItem(
                                              value: selectedInvigilatorType,
                                              child: Text(
                                                selectedInvigilatorType!,
                                              ),
                                            ),
                                          ],
                                    onChanged: null,
                                  ),
                            SizedBox(height: 12),
                          ],

                          // Email (moved here)
                          if (_showEmail) ...[
                            Text(
                              "Email",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 4),
                            TextField(
                              controller: emailController,
                              enabled: _isVerified,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                hintText: "Enter your email",
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                ),
                                filled: true,
                                fillColor: _isVerified
                                    ? Colors.white
                                    : Colors.grey.shade100,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Color.fromARGB(255, 68, 76, 231),
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          // Phone Number
                          if (_showPhone) ...[
                            Text(
                              "Phone Number",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 4),
                            TextField(
                              controller: phoneNumberController,
                              enabled: _isVerified,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                hintText: "Enter your phone number",
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                ),
                                filled: true,
                                fillColor: _isVerified
                                    ? Colors.white
                                    : Colors.grey.shade100,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Color.fromARGB(255, 68, 76, 231),
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                          ],

                          // City
                          if (_showCity) ...[
                            Text(
                              "City",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 4),
                            TextField(
                              controller: cityController,
                              enabled: _isVerified,
                              decoration: InputDecoration(
                                hintText: "Enter your city",
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                ),
                                filled: true,
                                fillColor: _isVerified
                                    ? Colors.white
                                    : Colors.grey.shade100,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Color.fromARGB(255, 68, 76, 231),
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                          ],

                          // Address
                          if (_showAddress) ...[
                            Text(
                              "Address",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 4),
                            TextField(
                              controller: addressController,
                              enabled: _isVerified,
                              decoration: InputDecoration(
                                hintText: "Enter your address",
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                ),
                                filled: true,
                                fillColor: _isVerified
                                    ? Colors.white
                                    : Colors.grey.shade100,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.white),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Color.fromARGB(255, 68, 76, 231),
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Register Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: !_isVerified || _isValidating
                                  ? null
                                  : () async {
                                      if (fullNameController.text
                                              .trim()
                                              .isEmpty &&
                                          _showFullName) {
                                        _showErrorDialog(
                                          'Please enter your full name.',
                                        );
                                        return;
                                      }
                                      if (emailController.text.trim().isEmpty &&
                                          _showEmail) {
                                        _showErrorDialog(
                                          'Please enter your email address.',
                                        );
                                        return;
                                      }
                                      if (widget.isFreshRegistration) {
                                        if (centreController.text
                                                .trim()
                                                .isEmpty &&
                                            _showCentre) {
                                          _showErrorDialog(
                                            'Please enter your assigned exam centre.',
                                          );
                                          return;
                                        }
                                        if (invigilatorTypeController.text
                                                .trim()
                                                .isEmpty &&
                                            _showType) {
                                          _showErrorDialog(
                                            'Please enter your invigilator role.',
                                          );
                                          return;
                                        }
                                      } else {
                                        if (selectedCentre == null &&
                                            _showCentre) {
                                          _showErrorDialog(
                                            'Please select your assigned exam centre.',
                                          );
                                          return;
                                        }
                                        if (selectedInvigilatorType == null &&
                                            _showType) {
                                          _showErrorDialog(
                                            'Please select your invigilator role.',
                                          );
                                          return;
                                        }
                                      }

                                      if (phoneNumberController.text
                                              .trim()
                                              .isEmpty &&
                                          _showPhone) {
                                        _showErrorDialog(
                                          'Please enter your phone number.',
                                        );
                                        return;
                                      }
                                      if (cityController.text.trim().isEmpty &&
                                          _showCity) {
                                        _showErrorDialog(
                                          'Please enter your city.',
                                        );
                                        return;
                                      }
                                      if (addressController.text
                                              .trim()
                                              .isEmpty &&
                                          _showAddress) {
                                        _showErrorDialog(
                                          'Please enter your address.',
                                        );
                                        return;
                                      }

                                      setState(() {
                                        _showFaceRegisterView = true;
                                      });
                                    },
                              child: _isValidating
                                  ? CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : Text("Register"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color.fromARGB(
                                  255,
                                  68,
                                  76,
                                  231,
                                ),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
      bottomNavigationBar: const AppFooter(),
    );
  }
}

class FaceVerificationDialog extends StatefulWidget {
  final String trainingTemplate;
  final String userName;

  const FaceVerificationDialog({
    super.key,
    required this.trainingTemplate,
    required this.userName,
  });

  @override
  State<FaceVerificationDialog> createState() => _FaceVerificationDialogState();
}

class _FaceVerificationDialogState extends State<FaceVerificationDialog> {
  bool _isVerifying = false;
  String _statusMessage = 'Tap "Verify" to capture your face.';

  int _attemptCount = 0;
  final int _maxAttempts = 3;
  bool _showRetryButton = false;

  Future<void> _captureAndVerify() async {
    if (_isVerifying) {
      return;
    }

    if (_attemptCount >= _maxAttempts) {
      setState(() {
        _statusMessage = 'Maximum attempts reached.';
        _showRetryButton = false;
      });

      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        Navigator.of(context).pop(
          VerificationResult(
            isVerified: false,
            message: 'Face verification was unsuccessful.',
            similarity: 0.0,
            maxAttemptsReached: true,
          ),
        );
        debugPrint(' Verification failed after $_maxAttempts attempts.');
      }
      return;
    }

    try {
      setState(() {
        _isVerifying = true;
        _showRetryButton = false;
        _attemptCount++;
        _statusMessage =
            'Opening camera... (Attempt $_attemptCount/$_maxAttempts)';
      });

      // Use FaceCameraPage with real-time face detection
      final XFile? imageFile = await Navigator.push<XFile>(
        context,
        MaterialPageRoute(
          builder: (context) => const FaceCaptureGuidePage(
            title: 'Face Verification Guide',
            nextPage: FaceCameraPage(
              title: 'Verify Your Identity',
              instructionText: 'Position your face inside the frame to verify',
              autoCapture: true, // Auto capture for verification
            ),
          ),
        ),
      );

      if (imageFile == null) {
        // User cancelled camera
        setState(() {
          _statusMessage = 'Camera cancelled. Tap Verify to try again.';
          _isVerifying = false;
          _showRetryButton = true;
        });
        return;
      }

      setState(() {
        _statusMessage = 'Verifying your identity...';
      });

      final verificationEmbedding =
          await FaceRecognitionServiceEnhanced.generateEmbedding(
            imageFile.path,
          );

      if (verificationEmbedding == null) {
        final remainingAttempts = _maxAttempts - _attemptCount;

        if (remainingAttempts == 0) {
          setState(() {
            _statusMessage =
                'No face detected!\n'
                'Maximum attempts reached.';
            _isVerifying = false;
            _showRetryButton = false;
          });

          await Future.delayed(const Duration(seconds: 2));

          if (mounted) {
            Navigator.of(context).pop(
              VerificationResult(
                isVerified: false,
                message:
                    'Face verification was unsuccessful. Please try again.',
                similarity: 0.0,
                maxAttemptsReached: true,
              ),
            );
            debugPrint(' Verification failed after $_maxAttempts attempts.');
          }
          return;
        }

        setState(() {
          _statusMessage =
              'No face detected!\n'
              '• Ensure good lighting\n'
              '• Face clearly visible\n\n'
              'Attempt $_attemptCount/$_maxAttempts';
          _isVerifying = false;
          _showRetryButton = true;
        });
        return;
      }

      final similarity = FaceRecognitionServiceEnhanced.compareFaces(
        widget.trainingTemplate,
        verificationEmbedding,
      );

      if (similarity >= 0.88) {
        setState(() {
          _statusMessage =
              'Verification Successful!\n'
              'Match: ${(similarity * 100).toStringAsFixed(1)}%';
        });

        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          Navigator.of(context).pop(
            VerificationResult(
              isVerified: true,
              message: 'Face verification successful!',
              similarity: similarity,
              maxAttemptsReached: false,
            ),
          );
        }
      } else {
        final remainingAttempts = _maxAttempts - _attemptCount;

        if (remainingAttempts == 0) {
          setState(() {
            _statusMessage =
                'Verification Failed!\n'
                'Match: ${(similarity * 100).toStringAsFixed(1)}%\n'
                'Maximum attempts reached.';
            _isVerifying = false;
            _showRetryButton = false;
          });

          await Future.delayed(const Duration(seconds: 2));

          if (mounted) {
            Navigator.of(context).pop(
              VerificationResult(
                isVerified: false,
                message:
                    'Face verification was unsuccessful. Please try again.',
                similarity: 0.0,
                maxAttemptsReached: true,
              ),
            );
            debugPrint(' Verification failed after $_maxAttempts attempts.');
          }
          return;
        }

        setState(() {
          _statusMessage =
              'Verification Failed!\n'
              'Match: ${(similarity * 100).toStringAsFixed(1)}%\n'
              'Attempts left: $remainingAttempts';
          _isVerifying = false;
          _showRetryButton = true;
        });
      }
    } catch (e) {
      final remainingAttempts = _maxAttempts - _attemptCount;

      if (remainingAttempts == 0) {
        setState(() {
          _statusMessage = 'Maximum attempts reached.\n';
          _isVerifying = false;
          _showRetryButton = false;
        });

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          Navigator.of(context).pop(
            VerificationResult(
              isVerified: false,
              message: 'Face verification was unsuccessful. Please try again.',
              similarity: 0.0,
              maxAttemptsReached: true,
            ),
          );
        }
        debugPrint(' Verification failed after $_maxAttempts attempts.');
        return;
      }

      setState(() {
        _statusMessage = 'Attempt $_attemptCount/$_maxAttempts';
        _isVerifying = false;
        _showRetryButton = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.blue[700], size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Face Verification',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isVerifying
                        ? null
                        : () => Navigator.of(context).pop(
                            VerificationResult(
                              isVerified: false,
                              message: 'Verification cancelled.',
                              similarity: 0.0,
                              maxAttemptsReached: false,
                            ),
                          ),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt, size: 64, color: Colors.blue[600]),
                    const SizedBox(height: 16),
                    Text(
                      'Tap "Verify" to start face check.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Position your face clearly\nand capture.',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_statusMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _statusMessage.contains('Successful')
                        ? Colors.green[50]
                        : _statusMessage.contains('Failed') ||
                              _statusMessage.contains('No face')
                        ? Colors.red[50]
                        : Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _statusMessage.contains('Successful')
                          ? Colors.green[300]!
                          : _statusMessage.contains('Failed') ||
                                _statusMessage.contains('No face')
                          ? Colors.red[300]!
                          : Colors.blue[300]!,
                    ),
                  ),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: 13,
                      color: _statusMessage.contains('Successful')
                          ? Colors.green[800]
                          : _statusMessage.contains('Failed') ||
                                _statusMessage.contains('No face')
                          ? Colors.red[800]
                          : Colors.blue[800],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isVerifying
                          ? null
                          : () {
                              Navigator.of(context).pop(
                                VerificationResult(
                                  isVerified: false,
                                  message: 'Verification was cancelled.',
                                  similarity: 0.0,
                                  maxAttemptsReached: false,
                                ),
                              );
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isVerifying ? null : _captureAndVerify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _showRetryButton
                                  ? 'Retry ($_attemptCount/$_maxAttempts)'
                                  : 'Verify',
                              style: const TextStyle(color: Colors.white),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VerificationResult {
  final bool isVerified;
  final String message;
  final double similarity;
  final bool maxAttemptsReached;

  VerificationResult({
    required this.isVerified,
    required this.message,
    required this.similarity,
    this.maxAttemptsReached = false,
  });
}
