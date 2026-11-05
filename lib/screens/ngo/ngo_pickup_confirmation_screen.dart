import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NgoPickupConfirmationScreen extends StatefulWidget {
  final String donationId;

  const NgoPickupConfirmationScreen({
    super.key,
    required this.donationId,
  });

  @override
  State<NgoPickupConfirmationScreen> createState() =>
      _NgoPickupConfirmationScreenState();
}

class _NgoPickupConfirmationScreenState
    extends State<NgoPickupConfirmationScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _minutesController =
      TextEditingController();

  bool _capacityConfirmed = false;
  bool _detailsReviewed = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  Future<void> _confirmPickup() async {
    if (_isSaving) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (!_capacityConfirmed || !_detailsReviewed) {
      _showError(
        'Please confirm receiving capacity and review '
        'the Donation Passport details.',
      );
      return;
    }

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showError('Your session has ended. Please log in again.');
      return;
    }

    final int? minutes = int.tryParse(
      _minutesController.text.trim(),
    );

    if (minutes == null || minutes <= 0) {
      _showError('Enter a valid number of minutes.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
    });

    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      final DocumentReference<Map<String, dynamic>> donationRef =
          firestore.collection('donations').doc(widget.donationId);

      final DocumentReference<Map<String, dynamic>> profileRef =
          firestore.collection('users').doc(user.uid);

      await firestore.runTransaction((transaction) async {
        // Complete all reads before making any writes.
        final profileSnapshot = await transaction.get(profileRef);
        final donationSnapshot = await transaction.get(donationRef);

        final Map<String, dynamic>? profile = profileSnapshot.data();
        final Object? rawRole = profile?['role'];

        final String role =
            rawRole is String ? rawRole.trim().toLowerCase() : '';

        if (role != 'ngo' || profile?['isActive'] == false) {
          throw StateError(
            'An active NGO profile is required to confirm pickup.',
          );
        }

        final Map<String, dynamic>? donation = donationSnapshot.data();

        if (!donationSnapshot.exists || donation == null) {
          throw StateError('This donation no longer exists.');
        }

        if (donation['claimedByNgoId'] != user.uid) {
          throw StateError(
            'Only the NGO that claimed this donation can confirm pickup.',
          );
        }

        if (donation['status'] != 'claimed') {
          throw StateError(
            'Pickup confirmation is available only for claimed donations.',
          );
        }

        if (donation['ngoPickupConfirmed'] == true) {
          throw StateError('Pickup has already been confirmed.');
        }

        final Object? eligibility = donation['eligibilityStatus'];

        if (eligibility != 'eligible' && eligibility != 'urgent') {
          throw StateError(
            'This donation is not currently eligible for ordinary pickup. '
            'Manual-review donations need a separate review workflow.',
          );
        }

        final Object? rawDeadline = donation['pickupDeadline'];

        if (rawDeadline is! Timestamp) {
          throw StateError(
            'The donation has no valid pickup deadline.',
          );
        }

        final DateTime now = DateTime.now();
        final DateTime deadline = rawDeadline.toDate();
        final DateTime plannedPickupAt = now.add(
          Duration(minutes: minutes),
        );

        if (!deadline.isAfter(now)) {
          throw StateError('The pickup window has closed.');
        }

        if (!plannedPickupAt.isBefore(deadline)) {
          throw StateError(
            'The planned pickup must be before the donation deadline. '
            'Choose an earlier pickup time.',
          );
        }

        final Object? rawQuantity = donation['quantity'];

        if (rawQuantity is! num ||
            !rawQuantity.isFinite ||
            rawQuantity <= 0) {
          throw StateError(
            'The donation has no valid quantity to confirm.',
          );
        }

        transaction.update(donationRef, {
          'ngoCapacityConfirmed': true,
          'ngoConfirmedQuantity': rawQuantity,
          'ngoDetailsReviewed': true,
          'ngoPickupConfirmed': true,
          'ngoPickupConfirmedAt': FieldValue.serverTimestamp(),
          'plannedPickupAt': Timestamp.fromDate(plannedPickupAt),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text(
              'NGO capacity and pickup time confirmed.',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );

      Navigator.of(context).pop(true);
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'NGO pickup confirmation failed: '
        '${error.code} - ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showError(
        'Unable to save pickup confirmation. (${error.code})',
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      _showError(error.message.toString());
    } catch (error, stackTrace) {
      debugPrint('Unexpected pickup confirmation error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showError('Unable to confirm pickup. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Confirm NGO pickup'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Confirm receiving capacity',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Confirm that your NGO can receive the full donation '
                    'and that collection can happen before its pickup '
                    'deadline. Partial claims are not supported yet.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    'Donation ID: ${widget.donationId}',
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _minutesController,
                    enabled: !_isSaving,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Planned pickup in minutes',
                      hintText: 'Example: 20',
                      prefixIcon: Icon(Icons.schedule_outlined),
                      helperText:
                          'This is a planned time, not a volunteer booking.',
                    ),
                    validator: (value) {
                      final int? minutes = int.tryParse(
                        value?.trim() ?? '',
                      );

                      if (minutes == null || minutes <= 0) {
                        return 'Enter a positive whole number of minutes';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _capacityConfirmed,
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            setState(() {
                              _capacityConfirmed = value ?? false;
                            });
                          },
                    title: const Text(
                      'My NGO can receive the full listed quantity.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _detailsReviewed,
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            setState(() {
                              _detailsReviewed = value ?? false;
                            });
                          },
                    title: const Text(
                      'I reviewed the listed storage, packaging, '
                      'allergen information, and pickup deadline.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'This confirmation does not certify food safety. '
                    'Pickup inspection and final NGO acceptance '
                    'are still required.',
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _confirmPickup,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _isSaving
                            ? 'Saving confirmation...'
                            : 'Confirm capacity and pickup',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}