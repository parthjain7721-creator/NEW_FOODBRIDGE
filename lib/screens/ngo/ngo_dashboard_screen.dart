import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'donation_details_screen.dart';
import 'ngo_claimed_donations_screen.dart';
import 'ngo_delivery_inbox_screen.dart';
import 'ngo_receiving_settings_screen.dart';

class NgoDashboardScreen extends StatefulWidget {
  const NgoDashboardScreen({super.key});

  @override
  State<NgoDashboardScreen> createState() =>
      _NgoDashboardScreenState();
}

class _NgoDashboardScreenState extends State<NgoDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late Stream<QuerySnapshot<Map<String, dynamic>>> _donationsStream;

  Timer? _countdownTimer;
  DateTime _now = DateTime.now();

  String? _claimingDonationId;

  bool _isSigningOut = false;
  bool _isOpeningScreen = false;

  bool get _isBusy =>
      _claimingDonationId != null ||
      _isSigningOut ||
      _isOpeningScreen;

  @override
  void initState() {
    super.initState();

    _connectDonations();

    _countdownTimer = Timer.periodic(
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
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _connectDonations() {
    _donationsStream = _firestore
        .collection('donations')
        .where('status', isEqualTo: 'available')
        .snapshots();
  }

  void _retryDonations() {
    if (_isBusy) {
      return;
    }

    setState(() {
      _now = DateTime.now();
      _connectDonations();
    });
  }

  bool _sameAccount(String uid) {
    return mounted && _auth.currentUser?.uid == uid;
  }

  Future<void> _claimDonation(String donationId) async {
    if (_isBusy) {
      return;
    }

    final User? user = _auth.currentUser;

    if (user == null) {
      _showMessage(
        'Your session has ended. Please log in again.',
        Colors.red.shade700,
      );
      return;
    }

    final String uid = user.uid;

    setState(() {
      _claimingDonationId = donationId;
    });

    bool claimSucceeded = false;

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
            'Your account changed. Please start the claim again.',
          );
        }

        final Map<String, dynamic>? profile = profileSnapshot.data();

        if (profile == null ||
            profile['role'] != 'ngo' ||
            profile['isActive'] == false) {
          throw StateError(
            'An active NGO profile is required to claim donations.',
          );
        }

        final Map<String, dynamic>? donation = donationSnapshot.data();

        if (!donationSnapshot.exists || donation == null) {
          throw StateError('This donation no longer exists.');
        }

        if (donation['donorId'] == uid) {
          throw StateError('You cannot claim your own donation.');
        }

        if (donation['status'] != 'available') {
          throw StateError(
            'This donation is no longer available for claiming.',
          );
        }

        final Object? eligibility = donation['eligibilityStatus'];

        if (eligibility != 'eligible' && eligibility != 'urgent') {
          throw StateError(
            'This donation is not eligible for an ordinary claim. '
            'Manual-review donations require a separate review process.',
          );
        }

        final Object? rawDeadline = donation['pickupDeadline'];

        if (rawDeadline is! Timestamp) {
          throw StateError(
            'This donation has no valid pickup deadline.',
          );
        }

        if (!rawDeadline.toDate().isAfter(DateTime.now())) {
          throw StateError('The Food Rescue Window has closed.');
        }

        final Object? claimedByNgoId = donation['claimedByNgoId'];
        final Object? assignedVolunteerId =
            donation['assignedVolunteerId'];

        if (claimedByNgoId != null && claimedByNgoId != '') {
          throw StateError(
            'This donation already has a receiving NGO.',
          );
        }

        if (assignedVolunteerId != null &&
            assignedVolunteerId != '') {
          throw StateError(
            'This donation already has an assigned volunteer.',
          );
        }

        transaction.update(donationRef, {
          'status': 'claimed',
          'claimedByNgoId': uid,
          'claimedAt': FieldValue.serverTimestamp(),
          'ngoPickupConfirmed': false,
          'volunteerAssignmentStatus': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      claimSucceeded = true;
    } on FirebaseException catch (exception, stackTrace) {
      debugPrint(
        'NGO dashboard claim failed: '
        '${exception.code} - ${exception.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (_sameAccount(uid)) {
        _showMessage(
          exception.code == 'permission-denied'
              ? 'Firestore denied the claim. Check your NGO profile '
                  'and the published security rules.'
              : 'Unable to confirm the claim result. '
                  'Check My claimed donations before retrying. '
                  '(${exception.code})',
          Colors.red.shade700,
        );
      }
    } on StateError catch (exception) {
      if (_sameAccount(uid)) {
        _showMessage(
          exception.message.toString(),
          Colors.red.shade700,
        );
      }
    } catch (exception, stackTrace) {
      debugPrint('Unexpected donation claim error: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (_sameAccount(uid)) {
        _showMessage(
          'Unable to confirm the claim result. '
          'Check My claimed donations before retrying.',
          Colors.red.shade700,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _claimingDonationId = null;
        });
      }
    }

    if (!claimSucceeded || !_sameAccount(uid)) {
      return;
    }

    _showMessage(
      'Donation claimed. Confirm capacity and pickup time '
      'on the details screen.',
      Colors.green.shade700,
    );

    await _openDonationDetails(donationId);
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

      // AuthGate handles the transition back to Login.
    } catch (exception, stackTrace) {
      debugPrint('NGO logout failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to sign out. Please try again.',
        Colors.red.shade700,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  Future<void> _openScreen(Widget screen) async {
    if (_isBusy) {
      return;
    }

    if (_auth.currentUser == null) {
      _showMessage(
        'Your session has ended. Please log in again.',
        Colors.red.shade700,
      );
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

  Future<void> _openReceivingSettings() async {
    await _openScreen(const NgoReceivingSettingsScreen());
  }

  Future<void> _openClaimedDonations() async {
    await _openScreen(const NgoClaimedDonationsScreen());
  }

  Future<void> _openDeliveryInbox() async {
    await _openScreen(const NgoDeliveryInboxScreen());
  }

  Future<void> _openDonationDetails(String donationId) async {
    await _openScreen(
      DonationDetailsScreen(
        donationId: donationId,
      ),
    );
  }

  DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  String _readText(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return fallback;
  }

  String _quantityLabel(dynamic value) {
    if (value is num && value.isFinite && value > 0) {
      return '$value portions/packets';
    }

    return 'Not recorded';
  }

  bool _windowOpen(DateTime? deadline) {
    return deadline != null && deadline.isAfter(_now);
  }

  bool _ordinaryEligibility(String value) {
    return value == 'eligible' || value == 'urgent';
  }

  bool _canClaimListing(Map<String, dynamic> data) {
    final String? uid = _auth.currentUser?.uid;

    if (uid == null || data['donorId'] == uid) {
      return false;
    }

    return _ordinaryEligibility(
          _readText(data['eligibilityStatus'], ''),
        ) &&
        _windowOpen(
          _readDateTime(data['pickupDeadline']),
        );
  }

  String _formatRemainingTime(DateTime? deadline) {
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

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s remaining';
    }

    return '${minutes}m ${seconds}s remaining';
  }

  Color _countdownColor(DateTime? deadline) {
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

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Not recorded';
    }

    final DateTime local = value.toLocal();

    String twoDigits(int number) {
      return number.toString().padLeft(2, '0');
    }

    return '${twoDigits(local.day)}/${twoDigits(local.month)}/'
        '${local.year} ${twoDigits(local.hour)}:'
        '${twoDigits(local.minute)}';
  }

  String _storageLabel(String value) {
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

  String _eligibilityLabel(String value) {
    switch (value) {
      case 'eligible':
        return 'Eligible for pickup';
      case 'urgent':
        return 'Urgent pickup';
      case 'manual_review':
        return 'Needs manual review';
      case 'not_eligible':
        return 'Not eligible';
      default:
        return 'Unknown eligibility';
    }
  }

  Color _eligibilityColor(String value) {
    switch (value) {
      case 'eligible':
        return Colors.green.shade700;
      case 'urgent':
        return Colors.orange.shade800;
      case 'manual_review':
        return Colors.blue.shade700;
      case 'not_eligible':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  int _compareDonations(
    QueryDocumentSnapshot<Map<String, dynamic>> first,
    QueryDocumentSnapshot<Map<String, dynamic>> second,
  ) {
    final Map<String, dynamic> firstData = first.data();
    final Map<String, dynamic> secondData = second.data();

    final DateTime? firstDeadline =
        _readDateTime(firstData['pickupDeadline']);

    final DateTime? secondDeadline =
        _readDateTime(secondData['pickupDeadline']);

    final bool firstClaimable = _canClaimListing(firstData);
    final bool secondClaimable = _canClaimListing(secondData);

    if (firstClaimable != secondClaimable) {
      return firstClaimable ? -1 : 1;
    }

    if (firstDeadline == null && secondDeadline == null) {
      return first.id.compareTo(second.id);
    }

    if (firstDeadline == null) {
      return 1;
    }

    if (secondDeadline == null) {
      return -1;
    }

    final int comparison = firstDeadline.compareTo(secondDeadline);

    return comparison != 0
        ? comparison
        : first.id.compareTo(second.id);
  }

  void _showMessage(String message, Color color) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
  }

  Widget _buildNavigationCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 30,
                  color: const Color(0xFF356B4D),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(description),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isBusy ? null : onPressed,
                icon: Icon(icon),
                label: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildNavigationCard(
          icon: Icons.location_on_outlined,
          title: 'Receiving location and requirements',
          description:
              'Set your NGO receiving address, select its point '
              'on the map, and record your required quantity '
              'and preferred food categories.',
          buttonLabel: 'Manage receiving settings',
          onPressed: _openReceivingSettings,
        ),
        _buildNavigationCard(
          icon: Icons.inventory_outlined,
          title: 'My claimed donations',
          description:
              'Review the donations your NGO has claimed and '
              'confirm receiving capacity and pickup arrangements.',
          buttonLabel: 'View claimed donations',
          onPressed: _openClaimedDonations,
        ),
        _buildNavigationCard(
          icon: Icons.fact_check_outlined,
          title: 'Delivery inbox',
          description:
              'Find donations awaiting your NGO’s delivery review. '
              'Open a delivery to accept or reject it, or view '
              'previously accepted and rejected deliveries.',
          buttonLabel: 'Open delivery inbox',
          onPressed: _openDeliveryInbox,
        ),
      ],
    );
  }

  Widget _buildListingsError() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline,
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text(
              'Unable to load donation listings. '
              'Check your connection and NGO account access.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isBusy ? null : _retryDonations,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 16,
      ),
      child: Text(
        'FoodBridge records declarations and workflow checks. '
        'It does not certify food safety.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade700,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NGO Dashboard'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'NGO actions',
            enabled: !_isBusy,
            onSelected: (value) async {
              switch (value) {
                case 'receiving':
                  await _openReceivingSettings();
                  break;
                case 'claimed':
                  await _openClaimedDonations();
                  break;
                case 'deliveries':
                  await _openDeliveryInbox();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'receiving',
                child: Text('Receiving settings'),
              ),
              PopupMenuItem<String>(
                value: 'claimed',
                child: Text('My claimed donations'),
              ),
              PopupMenuItem<String>(
                value: 'deliveries',
                child: Text('Delivery inbox'),
              ),
            ],
            icon: const Icon(Icons.more_vert),
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
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _donationsStream,
          builder: (context, snapshot) {
            final donations =
                snapshot.data?.docs.toList() ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];

            donations.sort(_compareDonations);

            final int claimableCount = donations
                .where(
                  (document) => _canClaimListing(document.data()),
                )
                .length;

            final bool showListings =
                !snapshot.hasError &&
                snapshot.hasData &&
                donations.isNotEmpty;

            // Navigation + heading + listings/state + footer.
            final int contentCount =
                showListings ? donations.length : 1;

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: contentCount + 3,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildNavigationSection();
                }

                if (index == 1) {
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Padding(
                      padding: const EdgeInsets.only(
                        top: 8,
                        bottom: 16,
                      ),
                      child: Text(
                        'Food donation listings',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildHeader(
                      listingCount: donations.length,
                      claimableCount: claimableCount,
                    ),
                  );
                }

                final int contentIndex = index - 2;

                if (contentIndex == contentCount) {
                  return _buildFooter();
                }

                if (snapshot.hasError) {
                  return _buildListingsError();
                }

                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (donations.isEmpty) {
                  return const _EmptyDonationsView();
                }

                return _buildDonationCard(
                  donations[contentIndex],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader({
    required int listingCount,
    required int claimableCount,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 26,
              child: Icon(Icons.home_work_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Food donation listings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$listingCount listing(s) • '
                    '$claimableCount eligible with an open pickup window',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Eligible listings are shown first, '
                    'ordered by pickup deadline.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDonationCard(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final Map<String, dynamic> donation = document.data();

    final DateTime? deadline =
        _readDateTime(donation['pickupDeadline']);

    final String category = _readText(
      donation['foodCategory'],
      'Food donation',
    );

    final String eligibility = _readText(
      donation['eligibilityStatus'],
      'unknown',
    );

    final bool isOwnDonation =
        donation['donorId'] == _auth.currentUser?.uid;

    final bool windowOpen = _windowOpen(deadline);
    final bool canClaim = _canClaimListing(donation);

    final bool isClaimingThis =
        _claimingDonationId == document.id;

    final Color countdownColor = _countdownColor(deadline);

    final String buttonLabel;

    if (isClaimingThis) {
      buttonLabel = 'Claiming...';
    } else if (isOwnDonation) {
      buttonLabel = 'Your own donation';
    } else if (eligibility == 'manual_review') {
      buttonLabel = 'Manual review required';
    } else if (!_ordinaryEligibility(eligibility)) {
      buttonLabel = 'Not eligible for claim';
    } else if (deadline == null) {
      buttonLabel = 'Deadline missing';
    } else if (!windowOpen) {
      buttonLabel = 'Window closed';
    } else {
      buttonLabel = 'Claim donation';
    }

    return Card(
      key: ValueKey('listing-${document.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _StatusChip(
              label: _eligibilityLabel(eligibility),
              color: _eligibilityColor(eligibility),
            ),
            const SizedBox(height: 16),
            _InfoRow(
              icon: Icons.inventory_2_outlined,
              label: 'Quantity',
              value: _quantityLabel(donation['quantity']),
            ),
            _InfoRow(
              icon: Icons.kitchen_outlined,
              label: 'Storage',
              value: _storageLabel(
                _readText(donation['storageMethod'], 'unknown'),
              ),
            ),
            _InfoRow(
              icon: Icons.schedule_outlined,
              label: 'Pickup deadline',
              value: _formatDateTime(deadline),
            ),
            _InfoRow(
              icon: Icons.warning_amber_outlined,
              label: 'Allergens',
              value: _readText(
                donation['allergens'],
                'Not declared — not necessarily allergen-free',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: countdownColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: countdownColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatRemainingTime(deadline),
                      style: TextStyle(
                        color: countdownColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isBusy
                    ? null
                    : () => _openDonationDetails(document.id),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('View donation details'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canClaim && !_isBusy
                    ? () => _claimDonation(document.id)
                    : null,
                icon: isClaimingThis
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.volunteer_activism_outlined,
                      ),
                label: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: Colors.grey.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyDonationsView extends StatelessWidget {
  const _EmptyDonationsView();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 20),
            Text(
              'No donation listings',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'New listings will appear when donors publish donations. '
              'Use the cards above to manage receiving settings, '
              'open claimed donations, or review delivered donations.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}