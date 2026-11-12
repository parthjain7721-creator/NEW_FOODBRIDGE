import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/delivery_service.dart';
import '../../services/pickup_completion_service.dart';
import 'donation_qr_scan_screen.dart';
import 'pickup_inspection_screen.dart';
import 'volunteer_route_feasibility_screen.dart';

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
  StreamSubscription<User?>? _authSubscription;

  DateTime _now = DateTime.now();

  bool _isVerificationFlowOpen = false;
  bool _isDeliveryFlowOpen = false;
  bool _isReviewFlowOpen = false;
  bool _isRouteFeasibilityOpen = false;

  final PickupCompletionService _pickupCompletionService =
      PickupCompletionService();

  final DeliveryService _deliveryService = DeliveryService();

  bool get _isAnyFlowOpen =>
      _isVerificationFlowOpen ||
      _isDeliveryFlowOpen ||
      _isReviewFlowOpen ||
      _isRouteFeasibilityOpen;

  @override
  void initState() {
    super.initState();

    _connectTask();

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _connectTask();
      });
    });

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
    _authSubscription?.cancel();
    super.dispose();
  }

  void _connectTask() {
    _taskStream = FirebaseFirestore.instance
        .collection('donations')
        .doc(widget.donationId)
        .snapshots();
  }

  void _retry() {
    if (_isAnyFlowOpen) {
      return;
    }

    setState(() {
      _connectTask();
    });
  }

  bool _sameSession(String uid, String donationId) {
    return mounted &&
        FirebaseAuth.instance.currentUser?.uid == uid &&
        widget.donationId == donationId;
  }

  void _requireSameSession(String uid, String donationId) {
    if (!_sameSession(uid, donationId)) {
      throw StateError(
        'The account or task changed. '
        'Close this dialog and start again.',
      );
    }
  }

  Future<void> _checkCurrentTask(
    String donationId,
    String volunteerId,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('donations')
        .doc(donationId)
        .get(const GetOptions(source: Source.server));

    _requireSameSession(volunteerId, donationId);

    final data = snapshot.data();

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
      throw StateError(
        'This donation is not eligible for ordinary pickup.',
      );
    }

    final deadline = _date(data['pickupDeadline']);

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
    if (_isAnyFlowOpen) {
      return;
    }

    final volunteerId = FirebaseAuth.instance.currentUser?.uid;
    final donationId = widget.donationId;

    if (volunteerId == null) {
      _showSnackBar(
        'Your session has ended. Please log in again.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isVerificationFlowOpen = true;
    });

    try {
      await _checkCurrentTask(donationId, volunteerId);

      if (!mounted) {
        return;
      }

      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => DonationQrScanScreen(
            donationId: donationId,
          ),
        ),
      );

      if (!mounted || verified != true) {
        return;
      }

      _requireSameSession(volunteerId, donationId);
      await _checkCurrentTask(donationId, volunteerId);

      if (!mounted) {
        return;
      }

      final draft =
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

      _requireSameSession(volunteerId, donationId);

      if (draft.donationId != donationId) {
        throw StateError(
          'The inspection draft does not match this task.',
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

      await _checkCurrentTask(donationId, volunteerId);

      if (!mounted) {
        return;
      }

      await _showDraftReview(
        draft,
        volunteerId: volunteerId,
        donationId: donationId,
      );
    } catch (exception, stackTrace) {
      debugPrint('Pickup inspection flow failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (_sameSession(volunteerId, donationId)) {
        _showSnackBar(
          _operationError(exception, 'verify pickup'),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerificationFlowOpen = false;
        });
      }
    }
  }

  Future<void> _openRouteFeasibility(
    Map<String, dynamic> data,
  ) async {
    if (_isAnyFlowOpen) {
      return;
    }

    final volunteerId = FirebaseAuth.instance.currentUser?.uid;
    final donationId = widget.donationId;

    if (volunteerId == null) {
      _showSnackBar(
        'Your session has ended. Please log in again.',
        isError: true,
      );
      return;
    }

    final Object? pickup = data['pickupLocation'];
    final Object? receivingNgoId = data['claimedByNgoId'];

    if (pickup is! GeoPoint) {
      _showSnackBar(
        'The donor pickup location is not available.',
        isError: true,
      );
      return;
    }

    if (receivingNgoId is! String || receivingNgoId.trim().isEmpty) {
      _showSnackBar(
        'The receiving NGO is not available for this task.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isRouteFeasibilityOpen = true;
    });

    try {
      final receivingSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(receivingNgoId)
          .get(const GetOptions(source: Source.server));

      if (!_sameSession(volunteerId, donationId)) {
        return;
      }

      final receivingData = receivingSnapshot.data();

      if (!receivingSnapshot.exists || receivingData == null) {
        throw StateError(
          'The receiving NGO profile is no longer available.',
        );
      }

      final Object? rawSettings = receivingData['ngoReceivingProfile'];

      final Map<String, dynamic>? settings =
          rawSettings is Map<String, dynamic> ? rawSettings : null;

      final Object? receivingLocation = settings?['location'];
      final Object? rawAddress = settings?['address'];

      final String receivingAddress =
          rawAddress is String && rawAddress.trim().isNotEmpty
              ? rawAddress.trim()
              : 'Receiving address not recorded';

      if (receivingLocation is! GeoPoint) {
        throw StateError(
          'The receiving NGO has not saved a receiving location.',
        );
      }

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => VolunteerRouteFeasibilityScreen(
            donationId: donationId,
            donationTitle: _text(
              data['foodCategory'],
              'Food donation',
            ),
            pickupLocation: pickup,
            pickupAddress: _text(
              data['pickupAddress'],
              'Pickup address not recorded',
            ),
            receivingLocation: receivingLocation,
            receivingAddress: receivingAddress,
            pickupDeadline: _date(data['pickupDeadline']),
          ),
        ),
      );
    } on FirebaseException catch (exception, stackTrace) {
      debugPrint(
        'Route feasibility Firestore error: '
        '${exception.code} — ${exception.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (_sameSession(volunteerId, donationId)) {
        _showSnackBar(
          _routeFeasibilityFirestoreError(exception),
          isError: true,
        );
      }
    } catch (exception, stackTrace) {
      debugPrint('Route feasibility setup failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (_sameSession(volunteerId, donationId)) {
        _showSnackBar(
          exception is StateError
              ? exception.message
              : 'Unable to open route feasibility. '
                  '(${exception.runtimeType})',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRouteFeasibilityOpen = false;
        });
      }
    }
  }

  String _routeFeasibilityFirestoreError(FirebaseException exception) {
    switch (exception.code) {
      case 'permission-denied':
        return 'FoodBridge cannot read the receiving NGO’s location for '
            'this assigned task. The Firestore security rules currently '
            'prevent the volunteer from accessing it.';
      case 'unauthenticated':
        return 'Your session has ended. Please log in again.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Unable to load the receiving NGO location. '
            'Check your connection and try again.';
      default:
        return 'Unable to load the receiving NGO location. '
            '(${exception.code})';
    }
  }

  Future<void> _showDraftReview(
    PickupInspectionDraft draft, {
    required String volunteerId,
    required String donationId,
  }) async {
    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TaskActionDialog(
        title: 'Review and complete pickup',
        submitLabel: 'Record pickup',
        progressText:
            'Recording the photo fingerprint and pickup details...',
        information: [
          'Donation ID: $donationId',
          'Observed packaging: '
              '${_packagingLabel(draft.packagingCondition)}',
          'Inspection notes: '
              '${draft.notes.trim().isEmpty ? 'None entered' : draft.notes}',
          'Photo returned to app: '
              '${_formatDate(draft.photoReturnedAt)}',
          'The displayed photo time comes from your device. '
              'Firestore records a separate server timestamp '
              'when pickup is saved.',
          'Submit only after collecting the donation from the donor.',
          'Only inspection details and a SHA-256 photo fingerprint '
              'are recorded remotely. The image is not uploaded. '
              'This does not guarantee that the image will remain '
              'available on the device or certify food safety.',
        ],
        onSubmit: (_) async {
          _requireSameSession(volunteerId, donationId);

          await _pickupCompletionService.completePickup(
            donationId: donationId,
            localPhotoPath: draft.localPhotoPath,
            packagingCondition: draft.packagingCondition,
            notes: draft.notes,
          );
        },
        describeError: (exception) =>
            _operationError(exception, 'record pickup'),
      ),
    );

    if (completed == true &&
        _sameSession(volunteerId, donationId)) {
      _showSnackBar('Pickup recorded successfully.');
    }
  }

  Future<void> _showDeliveryHandoverDialog() async {
    if (_isAnyFlowOpen) {
      return;
    }

    final volunteerId = FirebaseAuth.instance.currentUser?.uid;
    final donationId = widget.donationId;

    if (volunteerId == null) {
      _showSnackBar(
        'Your session has ended. Please log in again.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isDeliveryFlowOpen = true;
    });

    try {
      final completed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TaskActionDialog(
          title: 'Confirm delivery handover',
          submitLabel: 'Confirm handover',
          progressText: 'Recording delivery handover...',
          information: [
            'Donation ID: $donationId',
            'Confirm only after physically handing over the donation '
                'to the receiving NGO.',
            'This records your handover declaration. '
                'NGO acceptance or rejection remains a separate step.',
          ],
          notesLabel: 'Handover notes (optional)',
          onSubmit: (notes) async {
            _requireSameSession(volunteerId, donationId);

            await _deliveryService.markDelivered(
              donationId: donationId,
              handoverNotes: notes,
            );
          },
          describeError: (exception) =>
              _operationError(exception, 'record delivery'),
        ),
      );

      if (completed == true &&
          _sameSession(volunteerId, donationId)) {
        _showSnackBar(
          'Delivery handover recorded. Awaiting NGO review.',
        );
      }
    } catch (exception, stackTrace) {
      debugPrint('Delivery dialog failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (_sameSession(volunteerId, donationId)) {
        _showSnackBar(
          _operationError(exception, 'record delivery'),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeliveryFlowOpen = false;
        });
      }
    }
  }

  Future<void> _showDeliveryReviewDialog({
    required bool accepted,
  }) async {
    if (_isAnyFlowOpen) {
      return;
    }

    final ngoId = FirebaseAuth.instance.currentUser?.uid;
    final donationId = widget.donationId;

    if (ngoId == null) {
      _showSnackBar(
        'Your session has ended. Please log in again.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isReviewFlowOpen = true;
    });

    try {
      final completed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TaskActionDialog(
          title: accepted ? 'Accept delivery' : 'Reject delivery',
          submitLabel: accepted ? 'Accept delivery' : 'Reject delivery',
          progressText: 'Recording NGO delivery review...',
          information: [
            'Donation ID: $donationId',
            accepted
                ? 'Confirm that your NGO has physically received '
                    'and reviewed this donation.'
                : 'Record why your NGO is rejecting this delivery.',
            'This decision is final in the current app workflow '
                'and does not certify food safety.',
          ],
          notesLabel: accepted
              ? 'Acceptance notes (optional)'
              : 'Rejection reason',
          requireNotes: !accepted,
          onSubmit: (reason) async {
            _requireSameSession(ngoId, donationId);

            await _deliveryService.reviewDelivery(
              donationId: donationId,
              accepted: accepted,
              reason: reason,
            );
          },
          describeError: (exception) =>
              _operationError(exception, 'record NGO review'),
        ),
      );

      if (completed == true && _sameSession(ngoId, donationId)) {
        _showSnackBar(
          accepted
              ? 'Delivery accepted successfully.'
              : 'Delivery rejected successfully.',
        );
      }
    } catch (exception, stackTrace) {
      debugPrint('NGO review dialog failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (_sameSession(ngoId, donationId)) {
        _showSnackBar(
          _operationError(exception, 'record NGO review'),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isReviewFlowOpen = false;
        });
      }
    }
  }

  String _operationError(Object exception, String operation) {
    if (exception is StateError) {
      return exception.message.toString();
    }

    if (exception is FirebaseException) {
      switch (exception.code) {
        case 'permission-denied':
          return 'Unable to $operation: Firestore denied the request. '
              'Check the published rules, your active account role, '
              'the donation assignment, and its current status.';

        case 'unauthenticated':
          return 'Your session has ended. Please log in again.';

        case 'unavailable':
        case 'deadline-exceeded':
        case 'aborted':
          return 'Unable to confirm the result. Check your connection '
              'and the latest task status before retrying. '
              '(${exception.code})';

        default:
          return 'Unable to $operation. (${exception.code})';
      }
    }

    return 'Unable to $operation. '
        'Check the latest task status before retrying.';
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

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

  Map<String, dynamic>? _map(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    return null;
  }

  DateTime? _date(dynamic value) {
    return value is Timestamp ? value.toDate() : null;
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Not recorded';
    }

    final local = value.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

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
        return 'Delivered — awaiting NGO review';
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

    final remaining = deadline.difference(_now);

    if (remaining <= Duration.zero) {
      return 'Pickup window closed';
    }

    return '${remaining.inHours}h '
        '${remaining.inMinutes.remainder(60)}m '
        '${remaining.inSeconds.remainder(60)}s remaining';
  }

  Color _windowColor(DateTime? deadline) {
    if (deadline == null) {
      return Colors.grey.shade700;
    }

    final remaining = deadline.difference(_now);

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
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Donation task details'),
      ),
      body: uid == null
          ? _message('Your session has ended. Please log in again.')
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              key: ValueKey('${widget.donationId}|$uid'),
              stream: _taskStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Unable to load this task. '
                            'Check your connection and account access.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isAnyFlowOpen ? null : _retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData ||
                    snapshot.connectionState ==
                        ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final document = snapshot.data!;
                final data = document.data();

                if (!document.exists || data == null) {
                  return _message('This donation no longer exists.');
                }

                final isVolunteer =
                    data['assignedVolunteerId'] == uid;
                final isReceivingNgo =
                    data['claimedByNgoId'] == uid;

                if (!isVolunteer && !isReceivingNgo) {
                  return _message(
                    'This task is not assigned to your volunteer '
                    'account or claimed by your NGO account.',
                  );
                }

                final status = _text(data['status'], 'unknown');
                final deadline = _date(data['pickupDeadline']);
                final plannedPickup = _date(data['plannedPickupAt']);

                final awaitingPickup =
                    status == 'volunteer_assigned';
                final assignmentActive =
                    data['volunteerAssignmentStatus'] == 'assigned';
                final windowOpen =
                    deadline != null && deadline.isAfter(_now);

                final confirmationsComplete =
                    data['ngoPickupConfirmed'] == true &&
                    data['ngoCapacityConfirmed'] == true &&
                    data['ngoDetailsReviewed'] == true &&
                    data['donorPickupConfirmed'] == true;

                final ordinarilyEligible =
                    data['eligibilityStatus'] == 'eligible' ||
                    data['eligibilityStatus'] == 'urgent';

                final Object? quantity = data['quantity'];

                final quantityConfirmed =
                    quantity is num &&
                    quantity.isFinite &&
                    quantity > 0 &&
                    data['ngoConfirmedQuantity'] == quantity;

                final canStartInspection =
                    isVolunteer &&
                    awaitingPickup &&
                    assignmentActive &&
                    windowOpen &&
                    confirmationsComplete &&
                    ordinarilyEligible &&
                    quantityConfirmed;

                final pickupInspection =
                    _map(data['pickupInspection']);
                final deliveryHandover =
                    _map(data['deliveryHandover']);
                final ngoReview =
                    _map(data['ngoDeliveryReview']);

                final pickupRecorded =
                    pickupInspection != null ||
                    data['pickedUpAt'] is Timestamp;

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
                          'Required confirmations, eligibility, or '
                          'quantity are incomplete. '
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
                          'The deadline has not been extended.',
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

                    if (awaitingPickup && isVolunteer)
                      _section('Route feasibility', [
                        const Text(
                          'Check whether the estimated driving route from your current '
                          'location to the pickup point and then to the NGO receiving '
                          'point can reasonably be completed before the pickup deadline.',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'This is an estimate only. It does not assign the task, guarantee '
                          'arrival, account for traffic conditions, or certify food safety.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: !_isAnyFlowOpen
                              ? () => _openRouteFeasibility(data)
                              : null,
                          icon: const Icon(Icons.route_outlined),
                          label: Text(
                            _isRouteFeasibilityOpen
                                ? 'Opening route feasibility...'
                                : 'Check route feasibility',
                          ),
                        ),
                      ]),

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

                    if (awaitingPickup && isVolunteer)
                      _section(
                        'QR verification and pickup inspection',
                        [
                          const Text(
                            'Scan the donor’s Donation Passport. '
                            'After a match, inspect packaging '
                            'and take a pickup photo.',
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed:
                                canStartInspection && !_isAnyFlowOpen
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
                            _formatDate(_date(data['pickedUpAt'])),
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
                                _date(pickupInspection['recordedAt']),
                              ),
                            ),
                            _field(
                              'Photo storage',
                              pickupInspection['photoStoredRemotely'] ==
                                      false
                                  ? 'Image not uploaded; '
                                      'local photo fingerprint recorded'
                                  : pickupInspection[
                                              'photoStoredRemotely'] ==
                                          true
                                      ? 'Marked as stored remotely'
                                      : 'Not recorded',
                            ),
                          ],
                        ] else
                          const Text(
                            'No pickup inspection has been recorded yet. '
                            'The pickup workflow records inspection '
                            'details and a photo fingerprint, '
                            'not a remotely stored image.',
                          ),
                      ],
                    ),

                    _section(
                      'Delivery and NGO review',
                      [
                        if (status == 'picked_up') ...[
                          const Text(
                            'Confirm delivery only after physical '
                            'handover to the receiving NGO.',
                          ),
                          if (isVolunteer) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed:
                                  !_isAnyFlowOpen &&
                                          pickupInspection != null
                                      ? _showDeliveryHandoverDialog
                                      : null,
                              icon: const Icon(Icons.local_shipping),
                              label: Text(
                                _isDeliveryFlowOpen
                                    ? 'Delivery dialog open...'
                                    : 'Confirm delivery handover',
                              ),
                            ),
                          ] else
                            const Text(
                              'Awaiting the volunteer’s handover record.',
                            ),
                        ] else if (status == 'delivered') ...[
                          _field(
                            'Delivery recorded at',
                            _formatDate(_date(data['deliveredAt'])),
                          ),
                          if (isReceivingNgo) ...[
                            const Text(
                              'Review the received donation and record '
                              'your NGO’s final decision.',
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed: _isAnyFlowOpen
                                      ? null
                                      : () =>
                                          _showDeliveryReviewDialog(
                                            accepted: true,
                                          ),
                                  icon: const Icon(Icons.check_circle),
                                  label: const Text('Accept delivery'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _isAnyFlowOpen
                                      ? null
                                      : () =>
                                          _showDeliveryReviewDialog(
                                            accepted: false,
                                          ),
                                  icon: const Icon(Icons.cancel),
                                  label: const Text('Reject delivery'),
                                ),
                              ],
                            ),
                          ] else
                            const Text(
                              'Awaiting review by the receiving NGO.',
                            ),
                        ] else if (status == 'accepted') ...[
                          _field(
                            'Accepted at',
                            _formatDate(_date(data['acceptedAt'])),
                          ),
                          const Text(
                            'The receiving NGO accepted this delivery.',
                          ),
                        ] else if (status == 'rejected') ...[
                          _field(
                            'Rejected at',
                            _formatDate(_date(data['rejectedAt'])),
                          ),
                          const Text(
                            'The receiving NGO rejected this delivery.',
                          ),
                        ] else
                          const Text(
                            'Delivery confirmation is available '
                            'only after pickup has been recorded.',
                          ),
                      ],
                    ),

                    if (deliveryHandover != null)
                      _section(
                        'Delivery handover record',
                        [
                          _field(
                            'Handover recorded at',
                            _formatDate(
                              _date(deliveryHandover['confirmedAt']),
                            ),
                          ),
                          _field(
                            'Handover notes',
                            _text(
                              deliveryHandover['notes'],
                              'No handover notes recorded',
                            ),
                          ),
                        ],
                      ),

                    if (ngoReview != null)
                      _section(
                        'NGO delivery review record',
                        [
                          _field(
                            'Decision',
                            _text(ngoReview['decision'], 'Not recorded'),
                          ),
                          _field(
                            'Reason or notes',
                            _text(
                              ngoReview['reason'],
                              'No review notes recorded',
                            ),
                          ),
                          _field(
                            'Reviewed at',
                            _formatDate(
                              _date(ngoReview['reviewedAt']),
                            ),
                          ),
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

class _TaskActionDialog extends StatefulWidget {
  final String title;
  final String submitLabel;
  final String progressText;
  final List<String> information;
  final String? notesLabel;
  final bool requireNotes;
  final Future<void> Function(String notes) onSubmit;
  final String Function(Object exception) describeError;

  const _TaskActionDialog({
    required this.title,
    required this.submitLabel,
    required this.progressText,
    required this.information,
    required this.onSubmit,
    required this.describeError,
    this.notesLabel,
    this.requireNotes = false,
  });

  @override
  State<_TaskActionDialog> createState() => _TaskActionDialogState();
}

class _TaskActionDialogState extends State<_TaskActionDialog> {
  final TextEditingController _notesController =
      TextEditingController();

  bool _isSubmitting = false;
  String? _submissionError;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final notes = _notesController.text.trim();

    if (widget.requireNotes && notes.isEmpty) {
      setState(() {
        _submissionError = 'Please enter a rejection reason.';
      });
      return;
    }

    if (notes.length > 500) {
      setState(() {
        _submissionError = 'Notes must contain 500 characters or fewer.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submissionError = null;
    });

    try {
      await widget.onSubmit(notes);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop<bool>(true);
    } catch (exception, stackTrace) {
      debugPrint('Task action failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _submissionError = widget.describeError(exception);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: !_isSubmitting,
      child: AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final paragraph in widget.information)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(paragraph),
                ),
              if (widget.notesLabel != null)
                TextField(
                  controller: _notesController,
                  enabled: !_isSubmitting,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: widget.notesLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
              if (_submissionError != null) ...[
                const SizedBox(height: 16),
                Text(
                  _submissionError!,
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_isSubmitting) ...[
                const SizedBox(height: 20),
                const Center(
                  child: CircularProgressIndicator(),
                ),
                const SizedBox(height: 12),
                Text(widget.progressText),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => Navigator.of(context).pop<bool>(false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: Text(
              _isSubmitting ? 'Recording...' : widget.submitLabel,
            ),
          ),
        ],
      ),
    );
  }
}