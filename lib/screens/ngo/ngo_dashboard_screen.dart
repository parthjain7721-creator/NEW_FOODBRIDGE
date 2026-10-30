import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'ngo_claimed_donations_screen.dart';

class NgoDashboardScreen extends StatefulWidget {
  const NgoDashboardScreen({super.key});

  @override
  State<NgoDashboardScreen> createState() =>
      _NgoDashboardScreenState();
}

class _NgoDashboardScreenState
    extends State<NgoDashboardScreen> {
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

  Stream<QuerySnapshot<Map<String, dynamic>>>
      _availableDonations() {
    return _firestore
        .collection('donations')
        .where('status', isEqualTo: 'available')
        .snapshots();
  }

  Future<void> _claimDonation(
    String donationId,
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
        _firestore.collection('donations').doc(donationId);

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

        final Timestamp? deadlineTimestamp =
            currentData['pickupDeadline'] as Timestamp?;

        if (deadlineTimestamp != null &&
            deadlineTimestamp
                .toDate()
                .isBefore(DateTime.now())) {
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

  void _openClaimedDonations() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            const NgoClaimedDonationsScreen(),
      ),
    );
  }

  String _formatRemainingTime(DateTime deadline) {
    final Duration remaining =
        deadline.difference(_now);

    if (remaining.isNegative ||
        remaining.inSeconds == 0) {
      return 'Window closed';
    }

    final int hours = remaining.inHours;
    final int minutes =
        remaining.inMinutes.remainder(60);
    final int seconds =
        remaining.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m remaining';
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

  String _formatDateTime(DateTime dateTime) {
    final DateTime local = dateTime.toLocal();

    String twoDigits(int value) {
      return value.toString().padLeft(2, '0');
    }

    return '${local.day}/${twoDigits(local.month)}/'
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
      case 'unknown':
        return 'Unknown';
      default:
        return value;
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
        return value;
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
        title: const Text('NGO Dashboard'),
        actions: [
          IconButton(
            tooltip: 'My claimed donations',
            onPressed: _openClaimedDonations,
            icon: const Icon(
              Icons.inventory_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await _auth.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: _availableDonations(),
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
                  'Unable to load available donations.\n\n'
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final documents =
              snapshot.data?.docs ?? [];

          if (documents.isEmpty) {
            return const _EmptyDonationsView();
          }

          final donations = documents.toList();

          donations.sort((first, second) {
            final DateTime firstDeadline =
                _readDateTime(
              first.data()['pickupDeadline'],
            );

            final DateTime secondDeadline =
                _readDateTime(
              second.data()['pickupDeadline'],
            );

            return firstDeadline
                .compareTo(secondDeadline);
          });

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _now = DateTime.now();
              });
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeader(
                  donations.length,
                ),
                const SizedBox(height: 16),
                ...donations
                    .map(_buildDonationCard),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(int donationCount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 26,
              child: Icon(
                Icons.home_work_outlined,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available food donations',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$donationCount donation(s) available',
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
    final Map<String, dynamic> donation =
        document.data();

    final DateTime deadline = _readDateTime(
      donation['pickupDeadline'],
    );

    final String category =
        donation['foodCategory'] as String? ??
            'Food donation';

    final String storage =
        donation['storageMethod'] as String? ??
            'unknown';

    final String eligibility =
        donation['eligibilityStatus'] as String? ??
            'unknown';

    final String allergens =
        donation['allergens'] as String? ?? '';

    final int quantity = _readInt(
      donation['quantity'],
    );

    final bool isExpired =
        deadline.isBefore(_now);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    category,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge,
                  ),
                ),
                _StatusChip(
                  label: _eligibilityLabel(
                    eligibility,
                  ),
                  color: _countdownColor(deadline),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _InfoRow(
              icon: Icons.inventory_2_outlined,
              label: 'Quantity',
              value: '$quantity portions/packets',
            ),
            _InfoRow(
              icon: Icons.kitchen_outlined,
              label: 'Storage',
              value: _storageLabel(storage),
            ),
            _InfoRow(
              icon: Icons.schedule_outlined,
              label: 'Pickup deadline',
              value: _formatDateTime(deadline),
            ),
            if (allergens.isNotEmpty)
              _InfoRow(
                icon: Icons.warning_amber_outlined,
                label: 'Allergens',
                value: allergens,
              ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: _countdownColor(deadline)
                    .withValues(alpha: 0.10),
                borderRadius:
                    BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color:
                        _countdownColor(deadline),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatRemainingTime(deadline),
                      style: TextStyle(
                        color: _countdownColor(
                          deadline,
                        ),
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
              child: ElevatedButton.icon(
                onPressed: isExpired
                    ? null
                    : () => _claimDonation(
                          document.id,
                          donation,
                        ),
                icon: const Icon(
                  Icons.volunteer_activism_outlined,
                ),
                label: Text(
                  isExpired
                      ? 'Window closed'
                      : 'Claim donation',
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      padding: const EdgeInsets.only(bottom: 8),
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
            width: 105,
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
      constraints: const BoxConstraints(
        maxWidth: 150,
      ),
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
        textAlign: TextAlign.center,
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 76,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 20),
            Text(
              'No donations available',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'New donations will appear here when donors '
              'create a Donation Passport.',
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