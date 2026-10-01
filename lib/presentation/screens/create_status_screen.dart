import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/services/api_client.dart';
import '../../data/services/media_preparation_service.dart';

/// Composes and publishes a new status ("story"). Supports either a plain text
/// status or an image picked from the gallery/camera.
class CreateStatusScreen extends StatefulWidget {
  const CreateStatusScreen({super.key});

  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _image;
  bool _posting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null && mounted) setState(() => _image = image);
    } catch (e) {
      _showError('Error picking image: $e');
    }
  }

  Future<void> _post() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _image == null) {
      _showError('Add some text or an image first');
      return;
    }

    setState(() => _posting = true);
    try {
      String? mediaPath;
      String? mediaType;

      if (_image != null) {
        // Same pre-flight gate as chat sends: fail here with an actionable
        // message instead of after a full upload.
        try {
          await MediaPreparationService.validate(
            filePath: _image!.path,
            messageType: AppConstants.messageTypeImage,
          );
        } on MediaValidationException catch (e) {
          throw Exception(e.message);
        }
        final upload =
            await _api.uploadFile(_image!.path, AppConstants.messageTypeImage);
        if (upload['success'] != true) {
          throw Exception(upload['message'] ?? 'Failed to upload image');
        }
        mediaPath = upload['url'];
        mediaType = upload['media_type'] ?? 'image/jpeg';
      }

      await _api.createStatus(
        text: text,
        mediaPath: mediaPath,
        mediaType: mediaType,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        _showError('Failed to post status: $e');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New status'),
        actions: [
          TextButton(
            onPressed: _posting ? null : _post,
            child: _posting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Post'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_image!.path),
                  height: 240,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(Icons.add_a_photo,
                      size: 48,
                      color: context.appColors.primaryEmphasis),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
                _ActionButton(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                _ActionButton(
                  icon: Icons.text_fields,
                  label: 'Text',
                  onTap: () => FocusScope.of(context).requestFocus(
                    FocusNode(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Share a thought...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon,
                size: 28, color: context.appColors.primaryEmphasis),
            const SizedBox(height: 4),
            Text(label, style: context.text.labelMedium),
          ],
        ),
      ),
    );
  }
}
