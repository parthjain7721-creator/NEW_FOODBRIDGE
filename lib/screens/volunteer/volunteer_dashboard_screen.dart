import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'volunteer_activity_screen.dart';
import 'volunteer_task_details_screen.dart';

class VolunteerDashboardScreen extends StatefulWidget {
  const VolunteerDashboardScreen({super.key});

  @override
  State<VolunteerDashboardScreen> createState() =>
      _VolunteerDashboardScreenState();
}

class _VolunteerDashboardScreenState
    extends State<VolunteerDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _availableStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _assignedStream;

  StreamSubscription<User?>? _authSubscription;

  Timer? _timer;
  DateTime _now = DateTime.now();

  String? _connectedUid;
  String? _acceptingId;

  bool _isSigningOut = false;
  bool _isAcceptanceDialogOpen = false;
  bool _isOpeningScreen = false;

  bool get _isBusy =>
      _acceptingId != null ||
      _isSigningOut ||
      _isAcceptanceDialogOpen ||
      _isOpeningScreen;

  @override
  void initState() {
    super.initState();

    _connectStreams();

    _authSubscription = _auth.authStateChanges().listen((user) {
      if (!mounted || user?.uid == _connectedUid) {
        return;
      }

      setState(() {
        _now = DateTime.now();
        _connectStreams();
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
  void dispose() {
    _timer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _connectStreams() {
    final String? uid = _auth.currentUser?.uid;

    _connectedUid = uid;

    if (uid == null) {
      _availableStream = null;
      _assignedStream = null;
      return;
    }

    _availableStream = _firestore
        .collection('donations')
        .where('status', isEqualTo: 'claimed')
        .where('ngoPickupConfirmed', isEqualTo: true)
        .where('donorPickupConfirmed', isEqualTo: true)
        .snapshots();

    _assignedStream = _firestore
        .collection('donations')
        .where('assignedVolunteerId', isEqualTo: uid)
        .snapshots();
  }

  void _retryStreams() {
    if (_isBusy) {
      return;
    }

    setState(() {
      _now = DateTime.now();
      _connectStreams();
    });
  }

  bool _sameAccount(String uid) {
    return mounted && _auth.currentUser?.uid == uid;
  }

  DateTime? _date(dynamic value) {
    return value is Timestamp ? value.toDate() : null;
  }

  String _text(dynamic value, String fallback) {
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : fallback;
  }

  String _quantityLabel(dynamic value) {
    if (value is num && value.isFinite && value > 0) {
      return '$value portions/packets';
    }

    return 'Not recorded';
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Not recorded';
    }

    final DateTime local = value.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
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

  String _statusLabel(dynamic value) {
    switch (value) {
      case 'volunteer_assigned':
        return 'Assigned to you';
      case 'picked_up':
        return 'Picked up — awaiting delivery';
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
        return 'Unknown status';
    }
  }

  String _remainingTime(DateTime? deadline) {
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

  Color _deadlineColor(DateTime? deadline) {
    if (deadline == null) {
      return Colors.grey.shade700;
    }

    final Duration remaining = deadline.difference(_now);

    if (remaining <= Duration.zero) {
      return Colors.red.shade700;
    }

    if (remaining <= const Duration(minutes: 30)) {
      return Colors.orange.shade800;
    }

    return Colors.green.shade700;
  }

  bool _validOpportunity(
    Map<String, dynamic> data,
    DateTime now,
  ) {
    final DateTime? deadline = _date(data['pickupDeadline']);
    final DateTime? planned = _date(data['plannedPickupAt']);
    final Object? quantity = data['quantity'];
    final Object? eligibility = data['eligibilityStatus'];

    return data['status'] == 'claimed' &&
        data['volunteerAssignmentStatus'] == 'pending' &&
        data['ngoPickupConfirmed'] == true &&
        data['donorPickupConfirmed'] == true &&
        data['ngoCapacityConfirmed'] == true &&
        data['ngoDetailsReviewed'] == true &&
        _text(data['claimedByNgoId'], '').isNotEmpty &&
        _text(data['assignedVolunteerId'], '').isEmpty &&
        quantity is num &&
        quantity.isFinite &&
        quantity > 0 &&
        data['ngoConfirmedQuantity'] == quantity &&
        (eligibility == 'eligible' || eligibility == 'urgent') &&
        deadline != null &&
        planned != null &&
        deadline.isAfter(now) &&
        planned.isAfter(now) &&
        planned.isBefore(deadline);
  }

  Future<void> _acceptTask(String donationId) async {
    if (_isBusy) {
      return;
    }

    final String? uid = _auth.currentUser?.uid;

    if (uid == null) {
      _message('Please log in again.', isError: true);
      return;
    }

    setState(() {
      _isAcceptanceDialogOpen = true;
    });

    bool? approved;

    try {
      approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Accept this pickup?'),
          content: const Text(
            'Accept only if you can collect the full donation '
            'at the planned time and before the pickup deadline.\n\n'
            'Location-based travel feasibility is not calculated yet. '
            'Confirm practical collection arrangements with the '
            'donor and NGO.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop<bool>(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop<bool>(true),
              child: const Text('Accept task'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAcceptanceDialogOpen = false;
        });
      }
    }

    if (!mounted || approved != true || _isBusy) {
      return;
    }

    if (!_sameAccount(uid)) {
      _message(
        'Your account changed. Please start again.',
        isError: true,
      );
      return;
    }

    setState(() {
      _acceptingId = donationId;
    });

    bool accepted = false;

    try {
      final DocumentReference<Map<String, dynamic>> donationRef =
          _firestore.collection('donations').doc(donationId);

      final DocumentReference<Map<String, dynamic>> profileRef =
          _firestore.collection('users').doc(uid);

      await _firestore.runTransaction<void>((transaction) async {
        // Complete all reads before writing.
        final profileSnapshot = await transaction.get(profileRef);
        final donationSnapshot = await transaction.get(donationRef);

        if (_auth.currentUser?.uid != uid) {
          throw StateError(
            'Your account changed. Please start again.',
          );
        }

        final Map<String, dynamic>? profile = profileSnapshot.data();

        if (profile == null ||
            profile['role'] != 'volunteer' ||
            profile['isActive'] == false) {
          throw StateError(
            'An active volunteer profile is required.',
          );
        }

        final Map<String, dynamic>? data = donationSnapshot.data();

        if (!donationSnapshot.exists || data == null) {
          throw StateError('This donation no longer exists.');
        }

        if (data['status'] != 'claimed' ||
            _text(data['assignedVolunteerId'], '').isNotEmpty ||
            data['volunteerAssignmentStatus'] != 'pending') {
          throw StateError(
            'This pickup is no longer available for assignment.',
          );
        }

        if (!_validOpportunity(data, DateTime.now())) {
          throw StateError(
            'This pickup is no longer eligible for assignment. '
            'Its confirmations, quantity, or pickup plan need attention.',
          );
        }

        transaction.update(donationRef, {
          'status': 'volunteer_assigned',
          'assignedVolunteerId': uid,
          'volunteerAssignmentStatus': 'assigned',
          'volunteerAssignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      accepted = true;
    } on FirebaseException catch (exception, stackTrace) {
      debugPrint(
        'Volunteer assignment failed: '
        '${exception.code} - ${exception.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (_sameAccount(uid)) {
        _message(
          exception.code == 'permission-denied'
              ? 'Assignment was denied. The task may no longer be '
                  'available, or its requirements are not satisfied.'
              : 'Unable to confirm the assignment result. '
                  'Check My tasks before retrying. '
                  '(${exception.code})',
          isError: true,
        );
      }
    } on StateError catch (exception) {
      if (_sameAccount(uid)) {
        _message(
          exception.message.toString(),
          isError: true,
        );
      }
    } catch (exception, stackTrace) {
      debugPrint('Unexpected assignment error: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (_sameAccount(uid)) {
        _message(
          'Unable to confirm the assignment result. '
          'Check My tasks before retrying.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _acceptingId = null;
        });
      }
    }

    if (!accepted || !_sameAccount(uid)) {
      return;
    }

    _message('Pickup accepted. Review your assigned task details.');

    await _openTaskDetails(donationId);
  }

  Future<void> _openScreen(Widget screen) async {
    if (_isBusy) {
      return;
    }

    if (_auth.currentUser == null) {
      _message('Please log in again.', isError: true);
      return;
    }

    setState(() {
      _isOpeningScreen = true;
    });

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => screen,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningScreen = false;
          _now = DateTime.now();
        });
      }
    }
  }

  Future<void> _openTaskDetails(String donationId) async {
    await _openScreen(
      VolunteerTaskDetailsScreen(
        donationId: donationId,
      ),
    );
  }

  Future<void> _openActivity() async {
    await _openScreen(const VolunteerActivityScreen());
  }

  Future<void> _logout() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      await _auth.signOut();

      // AuthGate handles the transition to Login.
    } catch (exception, stackTrace) {
      debugPrint('Volunteer logout failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _message(
          'Unable to sign out. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  void _message(String message, {bool isError = false}) {
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
        ),
      );
  }

  Widget _buildActivityCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.insights_outlined,
                  size: 30,
                  color: Color(0xFF356B4D),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'My volunteer activity',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'View assigned tasks, delivery outcomes, '
              'and your recorded volunteer activity.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _openActivity,
              icon: const Icon(Icons.history),
              label: const Text('View my activity'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Volunteer Dashboard'),
          actions: [
            IconButton(
              tooltip: 'My volunteer activity',
              onPressed: _isBusy ? null : _openActivity,
              icon: const Icon(Icons.insights_outlined),
            ),
            IconButton(
              tooltip: 'Logout',
              onPressed: _isBusy ? null : _logout,
              icon: _isSigningOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.volunteer_activism_outlined),
                text: 'Available pickups',
              ),
              Tab(
                icon: Icon(Icons.local_shipping_outlined),
                text: 'My tasks',
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _buildActivityCard(),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildList(_availableStream, available: true),
                    _buildList(_assignedStream, available: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    Stream<QuerySnapshot<Map<String, dynamic>>>? stream, {
    required bool available,
  }) {
    if (stream == null) {
      return const Center(
        child: Text('Please log in again.'),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey(
        '${_connectedUid}_${available ? 'available' : 'assigned'}',
      ),
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Unable to load pickup tasks. '
                    'Check your connection and volunteer account access.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isBusy ? null : _retryStreams,
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

        final documents = snapshot.data!.docs.where((document) {
          return !available ||
              _validOpportunity(document.data(), _now);
        }).toList();

        documents.sort((first, second) {
          final DateTime? a = _date(first.data()['pickupDeadline']);
          final DateTime? b = _date(second.data()['pickupDeadline']);

          if (a == null && b == null) {
            return first.id.compareTo(second.id);
          }

          if (a == null) {
            return 1;
          }

          if (b == null) {
            return -1;
          }

          final int comparison = a.compareTo(b);

          return comparison != 0
              ? comparison
              : first.id.compareTo(second.id);
        });

        if (documents.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    available
                        ? Icons.volunteer_activism_outlined
                        : Icons.local_shipping_outlined,
                    size: 64,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    available
                        ? 'No valid pickup opportunities right now.\n\n'
                            'Donor and NGO confirmations, a valid '
                            'quantity, and a future pickup plan '
                            'are required.'
                        : 'No tasks assigned to you yet.\n\n'
                            'Accept an opportunity from Available '
                            'pickups to get started.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildCard(
              documents[index],
              available: available,
            );
          },
        );
      },
    );
  }

  Widget _buildCard(
    QueryDocumentSnapshot<Map<String, dynamic>> document, {
    required bool available,
  }) {
    final Map<String, dynamic> data = document.data();

    final bool accepting = _acceptingId == document.id;
    final DateTime? deadline = _date(data['pickupDeadline']);

    final bool showCountdown =
        available || data['status'] == 'volunteer_assigned';

    final Color countdownColor = _deadlineColor(deadline);

    return Card(
      key: ValueKey(
        '${available ? 'opportunity' : 'task'}-${document.id}',
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _text(data['foodCategory'], 'Food donation'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text('Donation ID: ${document.id}'),
            const SizedBox(height: 8),
            Text('Quantity: ${_quantityLabel(data['quantity'])}'),
            const SizedBox(height: 8),
            Text(
              'Planned pickup: '
              '${_formatDate(_date(data['plannedPickupAt']))}',
            ),
            const SizedBox(height: 8),
            Text('Pickup deadline: ${_formatDate(deadline)}'),
            const SizedBox(height: 8),
            Text('Storage: ${_storageLabel(data['storageMethod'])}'),
            const SizedBox(height: 8),
            Text(
              'Allergens: '
              '${_text(data['allergens'], 'Not declared — do not assume allergen-free')}',
            ),
            if (showCountdown) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: countdownColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _remainingTime(deadline),
                  style: TextStyle(
                    color: countdownColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (available)
              ElevatedButton.icon(
                onPressed:
                    _isBusy ? null : () => _acceptTask(document.id),
                icon: accepting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  accepting ? 'Accepting...' : 'Accept pickup task',
                ),
              )
            else ...[
              Text(
                'Status: ${_statusLabel(data['status'])}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isBusy
                    ? null
                    : () => _openTaskDetails(document.id),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('View task details'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}