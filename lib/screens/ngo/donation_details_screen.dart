import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DonationDetailsScreen extends StatefulWidget {
  final String donationId;

  const DonationDetailsScreen({
    super.key,
    required this.donationId,
  });

  @override
  State<DonationDetailsScreen> createState() =>
      _DonationDetailsScreenState();
}

class _DonationDetailsScreenState
    extends State<DonationDetailsScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Timer? _countdownTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();

    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          setState(() {
            _now = DateTime.now();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _claimDonation(
    Map<String, dynamic> donation,
  ) async {
    final User? user = _auth.currentUser;

    if (user == null) {
      _showMessage(
        'Please log in again.',
        Colors.red.shade700,
      );
      return;
    }

    final DocumentReference<Map<String, dynamic>> donationRef =
        _firestore
            .collection('donations')
            .doc(widget.donationId);

    try {
      await _firestore.runTransaction((transaction) async {
        final DocumentSnapshot<Map<String, dynamic>> snapshot =
            await transaction.get(donationRef);

        if (!snapshot.exists) {
          throw Exception('Donation no longer exists.');
        }

        final Map<String, dynamic>? currentData =
            snapshot.data();

        if (currentData == null) {
          throw Exception('Donation data is unavailable.');
        }

        final String currentStatus =
            currentData['status'] as String? ?? 'unknown';

        if (currentStatus != 'available') {
          throw Exception(
            'This donation has already been claimed.',
          );
        }

        final Timestamp? deadline =
            currentData['pickupDeadline'] as Timestamp?;

        if (deadline != null &&
            deadline.toDate().isBefore(DateTime.now())) {
          throw Exception(
            'The Food Rescue Window has closed.',
          );
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
        'Donation claimed successfully.',
        Colors.green.shade700,
      );
    } catch (error) {
      debugPrint('Donation claim error: $error');

      if (!mounted) {
        return;
      }

      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        Colors.red.shade700,
      );
    }
  }

  DateTime _readDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return DateTime.now();
  }

  int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  String _formatDateTime(DateTime value) {
    final DateTime local = value.toLocal();

    String twoDigits(int number) {
      return number.toString().padLeft(2, '0');
    }

    return '${local.day}/${twoDigits(local.month)}/'
        '${local.year} ${twoDigits(local.hour)}:'
        '${twoDigits(local.minute)}';
  }

  String _formatRemainingTime(DateTime deadline) {
    final Duration remaining =
        deadline.difference(_now);

    if (remaining.isNegative ||
        remaining.inSeconds == 0) {
      return 'Rescue window closed';
    }

    final int hours = remaining.inHours;
    final int minutes =
        remaining.inMinutes.remainder(60);
    final int seconds =
        remaining.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s remaining';
    }

    return '${minutes}m ${seconds}s remaining';
  }

  Color _countdownColor(DateTime deadline) {
    final Duration remaining =
        deadline.difference(_now);

    if (remaining.isNegative) {
      return Colors.red.shade700;
    }

    if (remaining.inMinutes <= 30) {
      return Colors.orange.shade800;
    }

    return Colors.green.shade700;
  }

  String _storageLabel(String value) {
    switch (value) {
      case 'room_temperature':
        return 'Room temperature';
      case 'refrigerated':
        return 'Refrigerated';
      case 'frozen':
        return 'Frozen';
      case 'unknown':
        return 'Unknown';
      default:
        return value;
    }
  }

  String _packagingLabel(String value) {
    switch (value) {
      case 'sealed':
        return 'Sealed';
      case 'intact':
        return 'Intact';
      case 'damaged':
        return 'Damaged';
      case 'leaking':
        return 'Leaking';
      default:
        return value;
    }
  }

  String _eligibilityLabel(String value) {
    switch (value) {
      case 'eligible':
        return 'Eligible for pickup now';
      case 'urgent':
        return 'Urgent pickup required';
      case 'manual_review':
        return 'Needs manual NGO review';
      case 'not_eligible':
        return 'Not eligible for redistribution';
      default:
        return value;
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'available':
        return 'Available';
      case 'claimed':
        return 'Claimed by NGO';
      case 'volunteer_assigned':
        return 'Volunteer assigned';
      case 'picked_up':
        return 'Picked up';
      case 'delivered':
        return 'Delivered';
      case 'accepted':
        return 'Accepted by NGO';
      case 'rejected':
        return 'Rejected by NGO';
      case 'expired':
        return 'Expired';
      default:
        return value;
    }
  }

  Color _statusColor(String value) {
    switch (value) {
      case 'available':
        return Colors.green.shade700;
      case 'claimed':
        return Colors.blue.shade700;
      case 'volunteer_assigned':
        return Colors.indigo.shade700;
      case 'picked_up':
        return Colors.orange.shade800;
      case 'delivered':
        return Colors.teal.shade700;
      case 'accepted':
        return Colors.green.shade800;
      case 'rejected':
        return Colors.red.shade700;
      case 'expired':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Donation details'),
      ),
      body: StreamBuilder<
          DocumentSnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('donations')
            .doc(widget.donationId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load donation details.\n\n'
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final document = snapshot.data;

          if (document == null || !document.exists) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This donation no longer exists.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final Map<String, dynamic> donation =
              document.data() ?? {};

          final DateTime preparedAt = _readDateTime(
            donation['preparedAt'],
          );

          final DateTime postedAt = _readDateTime(
            donation['postedAt'],
          );

          final DateTime pickupDeadline =
              _readDateTime(
            donation['pickupDeadline'],
          );

          final String donationId =
              donation['donationId'] as String? ??
                  document.id;

          final String donorId =
              donation['donorId'] as String? ?? '';

          final String foodCategory =
              donation['foodCategory'] as String? ??
                  'Food donation';

          final String storageMethod =
              donation['storageMethod'] as String? ??
                  'unknown';

          final String packagingState =
              donation['packagingState'] as String? ??
                  'unknown';

          final String allergens =
              donation['allergens'] as String? ?? '';

          final String eligibilityStatus =
              donation['eligibilityStatus'] as String? ??
                  'unknown';

          final String status =
              donation['status'] as String? ??
                  'available';

          final int quantity = _readInt(
            donation['quantity'],
          );

          final String? claimedByNgoId =
              donation['claimedByNgoId'] as String?;

          final DateTime? claimedAt =
              donation['claimedAt'] is Timestamp
                  ? (donation['claimedAt'] as Timestamp)
                      .toDate()
                  : null;

          final bool isExpired =
              pickupDeadline.isBefore(_now);

          final bool isAvailable =
              status == 'available' && !isExpired;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                _buildHeaderCard(
                  donationId: donationId,
                  foodCategory: foodCategory,
                  status: status,
                ),
                const SizedBox(height: 16),
                _buildRescueWindowCard(
                  pickupDeadline: pickupDeadline,
                  isExpired: isExpired,
                ),
                const SizedBox(height: 16),
                _buildDonationPassportCard(
                  donationId: donationId,
                  donorId: donorId,
                  foodCategory: foodCategory,
                  quantity: quantity,
                  storageMethod: storageMethod,
                  packagingState: packagingState,
                  allergens: allergens,
                  preparedAt: preparedAt,
                  postedAt: postedAt,
                  pickupDeadline: pickupDeadline,
                  eligibilityStatus:
                      eligibilityStatus,
                ),
                const SizedBox(height: 16),
                _buildClaimInformationCard(
                  status: status,
                  claimedByNgoId: claimedByNgoId,
                  claimedAt: claimedAt,
                ),
                const SizedBox(height: 24),
                if (isAvailable)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _claimDonation(donation),
                      icon: const Icon(
                        Icons.volunteer_activism_outlined,
                      ),
                      label: const Text(
                        'Claim this donation',
                      ),
                    ),
                  ),
                if (!isAvailable)
                  _buildStatusNotice(
                    status: status,
                    isExpired: isExpired,
                  ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard({
    required String donationId,
    required String foodCategory,
    required String status,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              foodCategory,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Donation ID: $donationId',
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 14),
            _StatusChip(
              label: _statusLabel(status),
              color: _statusColor(status),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRescueWindowCard({
    required DateTime pickupDeadline,
    required bool isExpired,
  }) {
    final Color countdownColor =
        _countdownColor(pickupDeadline);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  color: countdownColor,
                ),
                const SizedBox(width: 10),
                Text(
                  'Food Rescue Window',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: countdownColor
                    .withValues(alpha: 0.10),
                borderRadius:
                    BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatRemainingTime(
                      pickupDeadline,
                    ),
                    style: TextStyle(
                      color: countdownColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pickup deadline: '
                    '${_formatDateTime(pickupDeadline)}',
                  ),
                ],
              ),
            ),
            if (isExpired)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'This donation cannot be claimed because '
                  'its Food Rescue Window has closed.',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDonationPassportCard({
    required String donationId,
    required String donorId,
    required String foodCategory,
    required int quantity,
    required String storageMethod,
    required String packagingState,
    required String allergens,
    required DateTime preparedAt,
    required DateTime postedAt,
    required DateTime pickupDeadline,
    required String eligibilityStatus,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.badge_outlined,
                  color: Color(0xFF356B4D),
                ),
                const SizedBox(width: 10),
                Text(
                  'Donation Passport',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoRow(
              icon: Icons.badge_outlined,
              label: 'Donation ID',
              value: donationId,
            ),
            _InfoRow(
              icon: Icons.person_outline,
              label: 'Donor ID',
              value: donorId,
            ),
            _InfoRow(
              icon: Icons.restaurant_outlined,
              label: 'Food category',
              value: foodCategory,
            ),
            _InfoRow(
              icon: Icons.inventory_2_outlined,
              label: 'Quantity',
              value: '$quantity portions/packets',
            ),
            _InfoRow(
              icon: Icons.kitchen_outlined,
              label: 'Storage method',
              value: _storageLabel(storageMethod),
            ),
            _InfoRow(
              icon: Icons.inventory_outlined,
              label: 'Packaging',
              value: _packagingLabel(packagingState),
            ),
            _InfoRow(
              icon: Icons.warning_amber_outlined,
              label: 'Allergens',
              value: allergens.isEmpty
                  ? 'None declared'
                  : allergens,
            ),
            _InfoRow(
              icon: Icons.schedule_outlined,
              label: 'Prepared at',
              value: _formatDateTime(preparedAt),
            ),
            _InfoRow(
              icon: Icons.post_add_outlined,
              label: 'Posted at',
              value: _formatDateTime(postedAt),
            ),
            _InfoRow(
              icon: Icons.timer_outlined,
              label: 'Pickup deadline',
              value: _formatDateTime(pickupDeadline),
            ),
            _InfoRow(
              icon: Icons.verified_outlined,
              label: 'Eligibility',
              value: _eligibilityLabel(
                eligibilityStatus,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClaimInformationCard({
    required String status,
    required String? claimedByNgoId,
    required DateTime? claimedAt,
  }) {
    final bool isClaimed = claimedByNgoId != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.home_work_outlined,
                  color: Color(0xFF356B4D),
                ),
                const SizedBox(width: 10),
                Text(
                  'NGO claim information',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isClaimed) ...[
              _InfoRow(
                icon: Icons.badge_outlined,
                label: 'Claimed by NGO',
                value: claimedByNgoId,
              ),
              if (claimedAt != null)
                _InfoRow(
                  icon: Icons.event_available_outlined,
                  label: 'Claimed at',
                  value: _formatDateTime(claimedAt),
                ),
              _InfoRow(
                icon: Icons.local_shipping_outlined,
                label: 'Volunteer status',
                value: _volunteerStatusLabel(
                  status,
                ),
              ),
            ] else
              const Text(
                'This donation has not been claimed yet.',
              ),
          ],
        ),
      ),
    );
  }

  String _volunteerStatusLabel(String status) {
    switch (status) {
      case 'claimed':
        return 'Waiting for volunteer assignment';
      case 'volunteer_assigned':
        return 'Volunteer assigned';
      case 'picked_up':
        return 'Picked up by volunteer';
      case 'delivered':
        return 'Delivered to NGO';
      case 'accepted':
        return 'Accepted by NGO';
      case 'rejected':
        return 'Rejected by NGO';
      default:
        return status;
    }
  }

  Widget _buildStatusNotice({
    required String status,
    required bool isExpired,
  }) {
    String message;

    if (isExpired) {
      message =
          'The Food Rescue Window has closed, so this donation cannot be claimed.';
    } else {
      message =
          'This donation is currently ${_statusLabel(status).toLowerCase()}.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: Colors.grey.shade700,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 115,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
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
        horizontal: 12,
        vertical: 7,
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