import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'donation_details_screen.dart';
import 'ngo_claimed_donations_screen.dart';

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

  bool get _isBusy =>
      _claimingDonationId != null || _isSigningOut;

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
    setState(() {
      _now = DateTime.now();
      _connectDonations();
    });
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

    setState(() {
      _claimingDonationId = donationId;
    });

    try {
      final DocumentReference<Map<String, dynamic>> donationRef =
          _firestore.collection('donations').doc(donationId);

      final DocumentReference<Map<String, dynamic>> profileRef =
          _firestore.collection('users').doc(user.uid);

      await _firestore.runTransaction((transaction) async {
        // Complete all reads before writing.
        final profileSnapshot = await transaction.get(profileRef);
        final donationSnapshot = await transaction.get(donationRef);

        final Map<String, dynamic>? profile = profileSnapshot.data();

        final String role = _readText(
          profile?['role'],
          '',
        ).toLowerCase();

        if (role != 'ngo' || profile?['isActive'] == false) {
          throw StateError(
            'An active NGO profile is required to claim donations.',
          );
        }

        final Map<String, dynamic>? donation = donationSnapshot.data();

        if (!donationSnapshot.exists || donation == null) {
          throw StateError('This donation no longer exists.');
        }

        if (donation['donorId'] == user.uid) {
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

        transaction.update(donationRef, {
          'status': 'claimed',
          'claimedByNgoId': user.uid,
          'claimedAt': FieldValue.serverTimestamp(),
          'ngoPickupConfirmed': false,
          'volunteerAssignmentStatus': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) {
        return;
      }

      _showMessage(
        'Donation claimed. Confirm capacity and pickup time '
        'on the details screen.',
        Colors.green.shade700,
      );

      _openDonationDetails(donationId);
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'NGO dashboard claim failed: '
        '${error.code} - ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        error.code == 'permission-denied'
            ? 'Firestore denied the claim. Check your NGO profile '
                'and the deployed security rules.'
            : 'Unable to claim donation. (${error.code})',
        Colors.red.shade700,
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        error.message.toString(),
        Colors.red.shade700,
      );
    } catch (error, stackTrace) {
      debugPrint('Unexpected donation claim error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to claim donation. Please try again.',
        Colors.red.shade700,
      );
    } finally {
      if (mounted) {
        setState(() {
          _claimingDonationId = null;
        });
      }
    }
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
    } catch (error, stackTrace) {
      debugPrint('NGO logout failed: $error');
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

  void _openClaimedDonations() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const NgoClaimedDonationsScreen(),
      ),
    );
  }

  void _openDonationDetails(String donationId) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DonationDetailsScreen(
          donationId: donationId,
        ),
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

    final DateTime? firstDeadline = _readDateTime(
      firstData['pickupDeadline'],
    );
    final DateTime? secondDeadline = _readDateTime(
      secondData['pickupDeadline'],
    );

    final bool firstClaimable =
        _ordinaryEligibility(
          _readText(firstData['eligibilityStatus'], ''),
        ) &&
        _windowOpen(firstDeadline);

    final bool secondClaimable =
        _ordinaryEligibility(
          _readText(secondData['eligibilityStatus'], ''),
        ) &&
        _windowOpen(secondDeadline);

    // Show eligible, open-window donations before blocked listings.
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

    return firstDeadline.compareTo(secondDeadline);
  }

  void _showMessage(String message, Color color) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NGO Dashboard'),
        actions: [
          IconButton(
            tooltip: 'My claimed donations',
            onPressed: _isBusy ? null : _openClaimedDonations,
            icon: const Icon(Icons.inventory_outlined),
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _donationsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to load donation listings.\n\n'
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _retryDonations,
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

          final donations = snapshot.data!.docs.toList();

          if (donations.isEmpty) {
            return const _EmptyDonationsView();
          }

          donations.sort(_compareDonations);

          final int claimableCount = donations.where((document) {
            final Map<String, dynamic> data = document.data();

            return _ordinaryEligibility(
                  _readText(data['eligibilityStatus'], ''),
                ) &&
                _windowOpen(
                  _readDateTime(data['pickupDeadline']),
                ) &&
                data['donorId'] != _auth.currentUser?.uid;
          }).length;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: donations.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildHeader(
                    listingCount: donations.length,
                    claimableCount: claimableCount,
                  ),
                );
              }

              return _buildDonationCard(donations[index - 1]);
            },
          );
        },
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

    final DateTime? deadline = _readDateTime(
      donation['pickupDeadline'],
    );

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

    final bool canClaim =
        _auth.currentUser != null &&
        !isOwnDonation &&
        _ordinaryEligibility(eligibility) &&
        windowOpen;

    final bool isClaimingThis =
        _claimingDonationId == document.id;

    final Color countdownColor = _countdownColor(deadline);

    String buttonLabel;

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
                        child: CircularProgressIndicator(strokeWidth: 2),
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
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 76,
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
              'Your claimed donations remain available through '
              'the inventory icon above.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}