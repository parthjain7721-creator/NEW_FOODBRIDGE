import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'donation_qr_scan_screen.dart';
import 'pickup_inspection_screen.dart';

import '../../services/pickup_completion_service.dart';

class VolunteerTaskDetailsScreen extends StatefulWidget {
  final String donationId;

  const VolunteerTaskDetailsScreen({
    super.key,
    required this.donationId,
  });

  @override
  State<VolunteerTaskDetailsScreen> createState() =>
      _VolunteerTaskDetailsScreenState();
}

class _VolunteerTaskDetailsScreenState
    extends State<VolunteerTaskDetailsScreen> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _taskStream;

  Timer? _timer;
  DateTime _now = DateTime.now();

  bool _isVerificationFlowOpen = false;

  final PickupCompletionService _pickupCompletionService =
      PickupCompletionService();

  @override
  void initState() {
    super.initState();

    _connectTask();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _now = DateTime.now();
        });
      },
    );
  }

  @override
  void didUpdateWidget(
    covariant VolunteerTaskDetailsScreen oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.donationId != widget.donationId) {
      _connectTask();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _connectTask() {
    _taskStream = FirebaseFirestore.instance
        .collection('donations')
        .doc(widget.donationId)
        .snapshots();
  }

  void _retry() {
    setState(() {
      _connectTask();
    });
  }

  bool _sameSession(String uid, String donationId) {
    return FirebaseAuth.instance.currentUser?.uid == uid &&
        widget.donationId == donationId;
  }

  Future<void> _checkCurrentTask(
    String donationId,
    String volunteerId,
  ) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await FirebaseFirestore.instance
            .collection('donations')
            .doc(donationId)
            .get(const GetOptions(source: Source.server));

    if (!_sameSession(volunteerId, donationId)) {
      throw StateError(
        'The account or task changed. Please start verification again.',
      );
    }

    final Map<String, dynamic>? data = snapshot.data();

    if (!snapshot.exists || data == null) {
      throw StateError('This donation no longer exists.');
    }

    if (data['assignedVolunteerId'] != volunteerId) {
      throw StateError('This task is no longer assigned to you.');
    }

    if (data['status'] != 'volunteer_assigned' ||
        data['volunteerAssignmentStatus'] != 'assigned') {
      throw StateError('This task is not currently awaiting pickup.');
    }

    if (data['ngoPickupConfirmed'] != true ||
        data['ngoCapacityConfirmed'] != true ||
        data['ngoDetailsReviewed'] != true ||
        data['donorPickupConfirmed'] != true) {
      throw StateError(
        'The required donor and NGO confirmations are incomplete.',
      );
    }

    if (data['eligibilityStatus'] != 'eligible' &&
        data['eligibilityStatus'] != 'urgent') {
      throw StateError('This donation is not eligible for ordinary pickup.');
    }

    final DateTime? deadline = _date(data['pickupDeadline']);

    if (deadline == null || !deadline.isAfter(DateTime.now())) {
      throw StateError(
        'The pickup window has closed or its deadline is missing.',
      );
    }

    final Object? quantity = data['quantity'];

    if (quantity is! num ||
        !quantity.isFinite ||
        quantity <= 0 ||
        data['ngoConfirmedQuantity'] != quantity) {
      throw StateError(
        'The confirmed donation quantity is missing or inconsistent.',
      );
    }
  }

  Future<void> _startPickupInspection() async {
    if (_isVerificationFlowOpen) {
      return;
    }

    final String? volunteerId =
        FirebaseAuth.instance.currentUser?.uid;

    if (volunteerId == null) {
      _showSnackBar(
        'Your session has ended. Please log in again.',
        isError: true,
      );
      return;
    }

    final String donationId = widget.donationId;

    setState(() {
      _isVerificationFlowOpen = true;
    });

    try {
      final bool? verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => DonationQrScanScreen(
            donationId: donationId,
          ),
        ),
      );

      if (!mounted || verified != true) {
        return;
      }

      if (!_sameSession(volunteerId, donationId)) {
        throw StateError(
          'The account or task changed. Please scan again.',
        );
      }

      await _checkCurrentTask(donationId, volunteerId);

      if (!mounted) {
        return;
      }

      final PickupInspectionDraft? draft =
          await Navigator.of(context).push<PickupInspectionDraft>(
        MaterialPageRoute<PickupInspectionDraft>(
          builder: (_) => PickupInspectionScreen(
            donationId: donationId,
          ),
        ),
      );

      if (!mounted || draft == null) {
        return;
      }

      if (!_sameSession(volunteerId, donationId) ||
          draft.donationId != donationId) {
        throw StateError(
          'The account or task changed. The draft was not submitted.',
        );
      }

      if (draft.packagingCondition != 'sealed' &&
          draft.packagingCondition != 'intact') {
        throw StateError(
          'This packaging inspection does not permit pickup to proceed.',
        );
      }

      if (draft.localPhotoPath.trim().isEmpty) {
        throw StateError('The inspection draft has no photo.');
      }

      // Recheck after inspection because the task may have changed
      // while the camera screen was open.
      await _checkCurrentTask(donationId, volunteerId);

      if (!mounted) {
        return;
      }

      await _showDraftReview(draft);
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Pickup verification failed: '
        '${error.code} - ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showSnackBar(
        'Unable to verify the current task. '
        'Check your connection and try again. (${error.code})',
        isError: true,
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      _showSnackBar(
        error.message.toString(),
        isError: true,
      );
    } catch (error, stackTrace) {
      debugPrint('Pickup inspection flow failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showSnackBar(
        'Unable to complete the inspection draft. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isVerificationFlowOpen = false;
        });
      }
    }
  }

  Future<void> _showDraftReview(PickupInspectionDraft draft) async {
    final String? volunteerId =
        FirebaseAuth.instance.currentUser?.uid;

    if (volunteerId == null) {
      _showSnackBar(
        'Your session has ended. Please log in again.',
        isError: true,
      );
      return;
    }

    if (draft.donationId != widget.donationId) {
      _showSnackBar(
        'The inspection draft does not match this task.',
        isError: true,
      );
      return;
    }

    bool isSubmitting = false;
    String? submissionError;

    final bool? completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submitPickup() async {
              if (isSubmitting) {
                return;
              }

              if (!_sameSession(volunteerId, draft.donationId)) {
                setDialogState(() {
                  submissionError =
                      'The account or task changed. '
                      'Close this dialog and start verification again.';
                });
                return;
              }

              setDialogState(() {
                isSubmitting = true;
                submissionError = null;
              });

              String? errorMessage;

              try {
                await _pickupCompletionService.completePickup(
                  donationId: draft.donationId,
                  localPhotoPath: draft.localPhotoPath,
                  packagingCondition: draft.packagingCondition,
                  notes: draft.notes,
                );

                if (!dialogContext.mounted) {
                  return;
                }

                Navigator.of(dialogContext).pop<bool>(true);
                return;
              } on FirebaseException catch (error, stackTrace) {
                debugPrint(
                  'Pickup evidence operation failed: '
                  '${error.plugin}/${error.code} - ${error.message}',
                );
                debugPrintStack(stackTrace: stackTrace);

                if (error.code == 'permission-denied') {
                  errorMessage =
                      'Pickup completion was denied by Firestore rules. '
                      'Confirm that the updated pickup rules are published '
                      'and that this task is assigned to your active '
                      'volunteer account.';
                } else if (error.code == 'unauthenticated') {
                  errorMessage =
                      'Your session has ended. Please log in again.';
                } else {
                  errorMessage =
                      'Unable to record pickup evidence. '
                      '(${error.code})';
                }
              } on StateError catch (error) {
                errorMessage = error.message.toString();
              } catch (error, stackTrace) {
                debugPrint('Unexpected pickup submission error: $error');
                debugPrintStack(stackTrace: stackTrace);

                errorMessage =
                    'Unable to confirm the submission result. '
                    'Retry this same draft or check the task status.';
              }

              if (!dialogContext.mounted) {
                return;
              }

              setDialogState(() {
                isSubmitting = false;
                submissionError = errorMessage;
              });
            }

            return PopScope(
              canPop: !isSubmitting,
              child: AlertDialog(
                title: const Text('Review and complete pickup'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        'Donation ID: ${draft.donationId}',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Observed packaging: '
                        '${_packagingLabel(draft.packagingCondition)}',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Inspection notes: '
                        '${draft.notes.isEmpty ? 'None entered' : draft.notes}',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Photo returned to app: '
                        '${_formatDate(draft.photoReturnedAt)}',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'The displayed photo time is from your device. '
                        'FoodBridge records a separate server timestamp '
                        'when it saves the pickup.',
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Submit only when the physical handover has '
                        'occurred and these observations describe '
                        'the donation you collected.\n\n'
                        'Submission records the inspection details and a '
                        'SHA-256 fingerprint of the locally retained photo. '
                        'The photo itself is not uploaded to Firebase '
                        'Storage. This does not certify food safety.',
                      ),
                      if (submissionError != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          submissionError!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (isSubmitting) ...[
                        const SizedBox(height: 20),
                        const Center(
                          child: CircularProgressIndicator(),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Recording pickup evidence and updating '
                          'the task status. Please wait.',
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop<bool>(false);
                          },
                    child: const Text('Close'),
                  ),
                  FilledButton(
                    onPressed: isSubmitting ? null : submitPickup,
                    child: Text(
                      isSubmitting
                          ? 'Submitting...'
                          : submissionError == null
                              ? 'Record pickup'
                              : 'Retry same submission',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || completed != true) {
      return;
    }

    if (!_sameSession(volunteerId, draft.donationId)) {
      return;
    }

    _showSnackBar(
      'Pickup recorded successfully. '
      'The task status will update from Firestore.',
    );
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? Colors.red.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
  }

  String _text(dynamic value, String fallback) {
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : fallback;
  }

  DateTime? _date(dynamic value) {
    return value is Timestamp ? value.toDate() : null;
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Not recorded';
    }

    final DateTime local = value.toLocal();

    String two(int number) {
      return number.toString().padLeft(2, '0');
    }

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _quantity(dynamic value) {
    if (value is num && value.isFinite && value > 0) {
      return '$value portions/packets';
    }

    return 'Not recorded';
  }

  String _storageLabel(dynamic value) {
    switch (value) {
      case 'room_temperature':
        return 'Room temperature';
      case 'refrigerated':
        return 'Refrigerated';
      case 'frozen':
        return 'Frozen';
      default:
        return 'Unknown';
    }
  }

  String _packagingLabel(dynamic value) {
    switch (value) {
      case 'sealed':
        return 'Sealed';
      case 'intact':
        return 'Intact';
      case 'damaged':
        return 'Damaged';
      case 'leaking':
        return 'Leaking';
      case 'uncertain':
        return 'Unable to assess';
      default:
        return 'Not recorded';
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'volunteer_assigned':
        return 'Assigned to volunteer';
      case 'picked_up':
        return 'Picked up';
      case 'delivered':
        return 'Delivered';
      case 'accepted':
        return 'Accepted by NGO';
      case 'rejected':
        return 'Rejected by NGO';
      case 'cancelled':
        return 'Cancelled';
      case 'expired':
        return 'Expired';
      default:
        return 'Unknown task status';
    }
  }

  String _remaining(DateTime? deadline) {
    if (deadline == null) {
      return 'Pickup deadline not recorded';
    }

    final Duration remaining = deadline.difference(_now);

    if (remaining <= Duration.zero) {
      return 'Pickup window closed';
    }

    final int hours = remaining.inHours;
    final int minutes = remaining.inMinutes.remainder(60);
    final int seconds = remaining.inSeconds.remainder(60);

    return '${hours}h ${minutes}m ${seconds}s remaining';
  }

  Color _windowColor(DateTime? deadline) {
    if (deadline == null) {
      return Colors.grey.shade700;
    }

    final Duration remaining = deadline.difference(_now);

    if (remaining <= Duration.zero) {
      return Colors.red.shade700;
    }

    if (remaining <= const Duration(minutes: 30)) {
      return Colors.orange.shade900;
    }

    return Colors.green.shade700;
  }

  Widget _notice(String message, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _message(String message) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pickup task details'),
      ),
      body: uid == null
          ? _message('Your session has ended. Please log in again.')
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _taskStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Unable to load this task.\n\n'
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed:
                                _isVerificationFlowOpen ? null : _retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final document = snapshot.data!;
                final Map<String, dynamic>? data = document.data();

                if (!document.exists || data == null) {
                  return _message('This donation no longer exists.');
                }

                if (data['assignedVolunteerId'] != uid) {
                  return _message(
                    'This task is not assigned to your account.',
                  );
                }

                final String status = _text(
                  data['status'],
                  'unknown',
                );

                final DateTime? deadline = _date(
                  data['pickupDeadline'],
                );

                final DateTime? plannedPickup = _date(
                  data['plannedPickupAt'],
                );

                final bool awaitingPickup =
                    status == 'volunteer_assigned';

                final bool assignmentActive =
                    data['volunteerAssignmentStatus'] == 'assigned';

                final bool windowOpen =
                    deadline != null && deadline.isAfter(_now);

                final bool confirmationsComplete =
                    data['ngoPickupConfirmed'] == true &&
                    data['ngoCapacityConfirmed'] == true &&
                    data['ngoDetailsReviewed'] == true &&
                    data['donorPickupConfirmed'] == true;

                final bool ordinarilyEligible =
                    data['eligibilityStatus'] == 'eligible' ||
                    data['eligibilityStatus'] == 'urgent';

                final Object? quantity = data['quantity'];

                final bool quantityConfirmed =
                    quantity is num &&
                    quantity.isFinite &&
                    quantity > 0 &&
                    data['ngoConfirmedQuantity'] == quantity;

                final bool canStartInspection =
                    awaitingPickup &&
                    assignmentActive &&
                    windowOpen &&
                    confirmationsComplete &&
                    ordinarilyEligible &&
                    quantityConfirmed;

                final bool pickupRecorded =
                    status == 'picked_up' ||
                    status == 'delivered' ||
                    status == 'accepted';

                final Map<String, dynamic>? pickupInspection =
                    data['pickupInspection'] is Map
                        ? data['pickupInspection']
                            as Map<String, dynamic>
                        : null;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _section(
                      _text(data['foodCategory'], 'Food donation'),
                      [
                        _field('Donation ID', document.id),
                        _field('Task status', _statusLabel(status)),
                        _field(
                          'Assigned at',
                          _formatDate(
                            _date(data['volunteerAssignedAt']),
                          ),
                        ),
                      ],
                    ),

                    if (awaitingPickup) ...[
                      _notice(
                        _remaining(deadline),
                        _windowColor(deadline),
                      ),
                      if (!windowOpen)
                        _notice(
                          'Do not proceed with collection: the pickup '
                          'window is closed or its deadline is missing.',
                          Colors.red.shade700,
                        ),
                      if (!confirmationsComplete ||
                          !ordinarilyEligible ||
                          !quantityConfirmed)
                        _notice(
                          'The required confirmations, eligibility, '
                          'or quantity are incomplete. '
                          'Do not proceed with collection.',
                          Colors.red.shade700,
                        ),
                      if (!assignmentActive)
                        _notice(
                          'The volunteer assignment is not active. '
                          'Do not proceed with collection.',
                          Colors.red.shade700,
                        ),
                      if (plannedPickup != null &&
                          !plannedPickup.isAfter(_now) &&
                          windowOpen)
                        _notice(
                          'The planned pickup time has been reached '
                          'or passed. Coordinate with the donor and NGO. '
                          'The pickup deadline has not been extended.',
                          Colors.orange.shade900,
                        ),
                    ],

                    _section(
                      'Pickup plan',
                      [
                        _field(
                          'Planned pickup',
                          _formatDate(plannedPickup),
                        ),
                        _field(
                          'Pickup deadline',
                          _formatDate(deadline),
                        ),
                        _field(
                          'Donor ID',
                          _text(data['donorId'], 'Not recorded'),
                        ),
                        _field(
                          'Receiving NGO ID',
                          _text(data['claimedByNgoId'], 'Not recorded'),
                        ),
                      ],
                    ),

                    _section(
                      'Donation Passport',
                      [
                        _field('Quantity', _quantity(data['quantity'])),
                        _field(
                          'Prepared at',
                          _formatDate(_date(data['preparedAt'])),
                        ),
                        _field(
                          'Posted at',
                          _formatDate(_date(data['postedAt'])),
                        ),
                        _field(
                          'Declared storage',
                          _storageLabel(data['storageMethod']),
                        ),
                        _field(
                          'Declared packaging',
                          _packagingLabel(data['packagingState']),
                        ),
                        _field(
                          'Allergen information',
                          _text(
                            data['allergens'],
                            'Not declared — do not assume allergen-free',
                          ),
                        ),
                      ],
                    ),

                    _section(
                      'Confirmation records',
                      [
                        _field(
                          'NGO capacity',
                          data['ngoCapacityConfirmed'] == true
                              ? 'Confirmed'
                              : 'Not confirmed',
                        ),
                        _field(
                          'NGO details review',
                          data['ngoDetailsReviewed'] == true
                              ? 'Confirmed'
                              : 'Not confirmed',
                        ),
                        _field(
                          'NGO pickup plan',
                          data['ngoPickupConfirmed'] == true
                              ? 'Confirmed'
                              : 'Not confirmed',
                        ),
                        _field(
                          'NGO confirmed quantity',
                          _quantity(data['ngoConfirmedQuantity']),
                        ),
                        _field(
                          'Donor pickup arrangement',
                          data['donorPickupConfirmed'] == true
                              ? 'Confirmed'
                              : 'Not confirmed',
                        ),
                        _field(
                          'NGO confirmation time',
                          _formatDate(
                            _date(data['ngoPickupConfirmedAt']),
                          ),
                        ),
                        _field(
                          'Donor confirmation time',
                          _formatDate(
                            _date(data['donorPickupConfirmedAt']),
                          ),
                        ),
                      ],
                    ),

                    if (awaitingPickup)
                      _section(
                        'QR verification and pickup inspection',
                        [
                          const Text(
                            'Scan the donor’s Donation Passport first. '
                            'After a match, record the observed packaging '
                            'condition and take a pickup photo.',
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed:
                                canStartInspection &&
                                        !_isVerificationFlowOpen
                                    ? _startPickupInspection
                                    : null,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: Text(
                              _isVerificationFlowOpen
                                  ? 'Verification in progress...'
                                  : 'Scan QR and inspect pickup',
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Damaged, leaking, or uncertain packaging '
                            'blocks progression in the inspection screen. '
                            'Acceptable packaging does not prove '
                            'that food is safe.',
                          ),
                        ],
                      ),

                    _section(
                      'Pickup evidence',
                      [
                        if (pickupRecorded) ...[
                          _field(
                            'Pickup recorded at',
                            _formatDate(
                              _date(data['pickedUpAt']),
                            ),
                          ),
                          if (pickupInspection != null) ...[
                            _field(
                              'Recorded packaging condition',
                              _packagingLabel(
                                pickupInspection['packagingCondition'],
                              ),
                            ),
                            _field(
                              'Inspection notes',
                              _text(
                                pickupInspection['notes'],
                                'No inspection notes recorded',
                              ),
                            ),
                            _field(
                              'Evidence recorded at',
                              _formatDate(
                                _date(
                                  pickupInspection['recordedAt'],
                                ),
                              ),
                            ),
                            _field(
                              'Photo storage',
                              pickupInspection['photoStoredRemotely'] == false
                                  ? 'Photo retained locally; SHA-256 '
                                      'fingerprint recorded'
                                  : 'Remote photo storage',
                            ),
                          ],
                          const Text(
                            'Pickup has been recorded. Delivery and final '
                            'NGO acceptance are separate steps.',
                          ),
                        ] else ...[
                          const Text(
                            'After QR matching and inspection, review the '
                            'draft and explicitly submit it. FoodBridge '
                            'records the inspection details and a SHA-256 '
                            'fingerprint of the locally retained photo. '
                            'The photo itself is not uploaded to Firebase '
                            'Storage.',
                          ),
                        ],
                      ],
                    ),

                    const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Text(
                        'FoodBridge records declarations and workflow '
                        'checks. It does not certify food safety.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}