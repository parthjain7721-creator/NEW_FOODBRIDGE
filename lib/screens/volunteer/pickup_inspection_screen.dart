import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PickupInspectionDraft {
  final String donationId;
  final String packagingCondition;
  final String notes;
  final String localPhotoPath;
  final DateTime photoReturnedAt;

  const PickupInspectionDraft({
    required this.donationId,
    required this.packagingCondition,
    required this.notes,
    required this.localPhotoPath,
    required this.photoReturnedAt,
  });
}

class PickupInspectionScreen extends StatefulWidget {
  final String donationId;

  const PickupInspectionScreen({
    super.key,
    required this.donationId,
  });

  @override
  State<PickupInspectionScreen> createState() =>
      _PickupInspectionScreenState();
}

class _PickupInspectionScreenState
    extends State<PickupInspectionScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _notesController =
      TextEditingController();

  String? _packagingCondition;

  XFile? _photo;
  DateTime? _photoReturnedAt;

  bool _isTakingPhoto = false;
  bool _isCheckingRecovery = true;
  bool _handoverReviewed = false;

  bool get _packagingAcceptable =>
      _packagingCondition == 'sealed' ||
      _packagingCondition == 'intact';

  @override
  void initState() {
    super.initState();
    _checkInterruptedCapture();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _checkInterruptedCapture() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final LostDataResponse response =
            await _picker.retrieveLostData();

        if (!mounted) {
          return;
        }

        if (!response.isEmpty) {
          // Do not attach recovered media to a task automatically.
          // Its original task association has not been persisted.
          _showMessage(
            'A previous camera session was interrupted. '
            'Please take a new photo for this donation.',
          );
        }
      }
    } catch (error) {
      debugPrint('Interrupted camera recovery check failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingRecovery = false;
        });
      }
    }
  }

  Future<void> _takePhoto() async {
    if (_isTakingPhoto || _isCheckingRecovery) {
      return;
    }

    setState(() {
      _isTakingPhoto = true;
    });

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );

      if (!mounted || photo == null) {
        return;
      }

      setState(() {
        _photo = photo;

        // This is when the camera result returned to the app.
        // It is not a trusted server timestamp or EXIF capture time.
        _photoReturnedAt = DateTime.now();
      });
    } catch (error, stackTrace) {
      debugPrint('Pickup camera capture failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to take a photo. Check camera permission and try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
        });
      }
    }
  }

  void _reviewDraft() {
    if (_isTakingPhoto || _isCheckingRecovery) {
      return;
    }

    if (_packagingCondition == null) {
      _showMessage('Select the observed packaging condition.');
      return;
    }

    if (!_packagingAcceptable) {
      _showMessage(
        'Do not proceed with pickup using this inspection result. '
        'Keep the donation uncollected and contact the donor and NGO.',
      );
      return;
    }

    final XFile? photo = _photo;
    final DateTime? returnedAt = _photoReturnedAt;

    if (photo == null || returnedAt == null) {
      _showMessage('Take a pickup photo first.');
      return;
    }

    if (!_handoverReviewed) {
      _showMessage('Confirm the handover inspection declaration.');
      return;
    }

    Navigator.of(context).pop<PickupInspectionDraft>(
      PickupInspectionDraft(
        donationId: widget.donationId,
        packagingCondition: _packagingCondition!,
        notes: _notesController.text.trim(),
        localPhotoPath: photo.path,
        photoReturnedAt: returnedAt,
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final XFile? photo = _photo;
    final bool busy = _isTakingPhoto || _isCheckingRecovery;

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pickup inspection draft'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Inspect before collection',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              SelectableText('Donation ID: ${widget.donationId}'),
              const SizedBox(height: 12),
              const Text(
                'Record what you observe at handover. '
                'Packaging checks and a photo do not prove food safety.',
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: _packagingCondition,
                decoration: const InputDecoration(
                  labelText: 'Observed packaging condition',
                  prefixIcon: Icon(Icons.inventory_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'sealed',
                    child: Text('Sealed'),
                  ),
                  DropdownMenuItem(
                    value: 'intact',
                    child: Text('Intact'),
                  ),
                  DropdownMenuItem(
                    value: 'damaged',
                    child: Text('Damaged'),
                  ),
                  DropdownMenuItem(
                    value: 'leaking',
                    child: Text('Leaking'),
                  ),
                  DropdownMenuItem(
                    value: 'uncertain',
                    child: Text('Unable to assess'),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        setState(() {
                          _packagingCondition = value;
                          _handoverReviewed = false;
                        });
                      },
              ),
              if (_packagingCondition != null &&
                  !_packagingAcceptable) ...[
                const SizedBox(height: 16),
                Text(
                  'Pickup is blocked for this inspection result. '
                  'Do not collect the donation. Contact the donor '
                  'and NGO for review.',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _notesController,
                enabled: !busy,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Inspection notes',
                  hintText:
                      'Record relevant packaging or handover observations.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (photo != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(photo.path),
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Unable to preview the photo. '
                          'Please take another photo.',
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: busy ? null : _takePhoto,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(
                  _isCheckingRecovery
                      ? 'Checking camera session...'
                      : _isTakingPhoto
                          ? 'Opening camera...'
                          : photo == null
                              ? 'Take pickup photo'
                              : 'Retake pickup photo',
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _handoverReviewed,
                onChanged: busy || !_packagingAcceptable
                    ? null
                    : (value) {
                        setState(() {
                          _handoverReviewed = value ?? false;
                        });
                      },
                title: const Text(
                  'I inspected the packaging and recorded '
                  'my observations for this donation.',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Draft only: the photo has not been uploaded, '
                'no server evidence record has been created, '
                'and the donation has not been marked picked up.',
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: busy || !_packagingAcceptable
                    ? null
                    : _reviewDraft,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review inspection draft'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}