import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../Services/storage/s3_transfer_helper.dart';
import '../core/security/image_encryption_service.dart';

/// Reusable widget that downloads an encrypted (or legacy unencrypted) image,
/// decrypts it client-side using [ImageEncryptionService.decryptImageBytes],
/// and renders it via [Image.memory].
///
/// Includes customizable loading indicator and error placeholder states.
class DecryptedImageWidget extends StatefulWidget {
  /// Remote HTTP / HTTPS URL of the image
  final String? imageUrl;

  /// Optional direct S3 object key (e.g. 'Supervisor-details/SUP123/face.jpg')
  final String? s3Key;

  /// Optional S3 bucket name (defaults to 'bits-supervisorapp')
  final String? s3Bucket;

  /// Optional pre-fetched binary bytes to decrypt and display directly
  final Uint8List? bytes;

  /// Image width
  final double? width;

  /// Image height
  final double? height;

  /// How the image should be inscribed into the box
  final BoxFit fit;

  /// Optional border radius for rounded corners
  final BorderRadius? borderRadius;

  /// Shape of the image container (e.g., BoxShape.circle or BoxShape.rectangle)
  final BoxShape shape;

  /// Custom widget to display during loading
  final Widget? placeholder;

  /// Custom widget to display on error
  final Widget? errorWidget;

  /// Icon size for the default error placeholder
  final double errorIconSize;

  /// Default error icon
  final IconData errorIcon;

  const DecryptedImageWidget({
    super.key,
    this.imageUrl,
    this.s3Key,
    this.s3Bucket,
    this.bytes,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.placeholder,
    this.errorWidget,
    this.errorIconSize = 36.0,
    this.errorIcon = Icons.person_rounded,
  });

  /// In-memory cache for decrypted image bytes to avoid re-decrypting across rebuilds
  static final Map<String, Uint8List> _decryptedMemoryCache = {};

  /// Clears the in-memory decrypted image cache
  static void clearMemoryCache() {
    _decryptedMemoryCache.clear();
  }

  @override
  State<DecryptedImageWidget> createState() => _DecryptedImageWidgetState();
}

class _DecryptedImageWidgetState extends State<DecryptedImageWidget> {
  Uint8List? _decryptedBytes;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAndDecrypt();
  }

  @override
  void didUpdateWidget(covariant DecryptedImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.s3Key != widget.s3Key ||
        oldWidget.bytes != widget.bytes) {
      _loadAndDecrypt();
    }
  }

  String? _getCacheKey() {
    if (widget.s3Key != null && widget.s3Key!.isNotEmpty) {
      return 's3://${widget.s3Bucket ?? "bits-supervisorapp"}/${widget.s3Key}';
    }
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      return widget.imageUrl;
    }
    return null;
  }

  Future<void> _loadAndDecrypt() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final cacheKey = _getCacheKey();
    if (cacheKey != null &&
        DecryptedImageWidget._decryptedMemoryCache.containsKey(cacheKey)) {
      if (!mounted) return;
      setState(() {
        _decryptedBytes = DecryptedImageWidget._decryptedMemoryCache[cacheKey];
        _isLoading = false;
      });
      return;
    }

    try {
      Uint8List? rawBytes;

      if (widget.bytes != null && widget.bytes!.isNotEmpty) {
        rawBytes = widget.bytes;
      } else if (widget.s3Key != null && widget.s3Key!.isNotEmpty) {
        rawBytes = await S3TransferHelper.download(
          bucket: widget.s3Bucket ?? 'bits-supervisorapp',
          key: widget.s3Key!,
        );
      } else if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
        final uri = Uri.tryParse(widget.imageUrl!);
        if (uri != null) {
          final response = await http.get(uri);
          if (response.statusCode >= 200 && response.statusCode < 300) {
            rawBytes = response.bodyBytes;
          } else {
            throw Exception(
              'HTTP GET failed with status code ${response.statusCode}',
            );
          }
        }
      }

      if (rawBytes == null || rawBytes.isEmpty) {
        throw Exception('No image data found');
      }

      // Decrypt the raw image bytes (or pass through unencrypted JPEG)
      final decrypted =
          await ImageEncryptionService.decryptImageBytes(rawBytes);

      if (cacheKey != null) {
        DecryptedImageWidget._decryptedMemoryCache[cacheKey] = decrypted;
      }

      if (!mounted) return;
      setState(() {
        _decryptedBytes = decrypted;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('🚨 [DecryptedImageWidget] Error loading image: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Widget _buildLoading() {
    if (widget.placeholder != null) {
      return widget.placeholder!;
    }
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[200],
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF444CE7)),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    if (widget.errorWidget != null) {
      return widget.errorWidget!;
    }
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[200],
      child: Center(
        child: Icon(
          widget.errorIcon,
          color: Colors.grey[500],
          size: widget.errorIconSize,
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (_isLoading) {
      return _buildLoading();
    }
    if (_errorMessage != null || _decryptedBytes == null) {
      return _buildError();
    }

    return Image.memory(
      _decryptedBytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('🚨 [DecryptedImageWidget] Image.memory rendering error: $error');
        return _buildError();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = _buildImage();

    if (widget.shape == BoxShape.circle) {
      content = ClipOval(child: content);
    } else if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    if (widget.width != null || widget.height != null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: content,
      );
    }

    return content;
  }
}
