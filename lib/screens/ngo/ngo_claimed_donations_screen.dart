import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'donation_details_screen.dart';

class NgoClaimedDonationsScreen extends StatefulWidget {
  const NgoClaimedDonationsScreen({super.key});

  @override
  State<NgoClaimedDonationsScreen> createState() =>
      _NgoClaimedDonationsScreenState();
}

class _NgoClaimedDonationsScreenState
    extends State<NgoClaimedDonationsScreen> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _donationsStream;

  Timer? _countdownTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();

    final String? ngoId = FirebaseAuth.instance.currentUser?.uid;

    if (ngoId != null) {
      _donationsStream = FirebaseFirestore.instance
          .collection('donations')
          .where('claimedByNgoId', isEqualTo: ngoId)
          .snapshots();
    }

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

  int _readInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Not recorded';
    }

    final DateTime local = value.toLocal();

    String twoDigits(int number) {
      return number.toString().padLeft(2, '0');
    }

    return '${twoDigits(local.day)}/'
        '${twoDigits(local.month)}/${local.year} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
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

  String _statusLabel(String value) {
    switch (value) {
      case 'available':
        return 'Available';
      case 'claimed':
        return 'Claimed';
      case 'volunteer_assigned':
        return 'Volunteer assigned';
      case 'picked_up':
        return 'Picked up';
      case 'delivered':
        return 'Delivered';
      case 'accepted':
        return 'Accepted';
      case 'rejected':
        return 'Rejected';
      case 'expired':
        return 'Expired';
      case 'cancelled':
        return 'Cancelled';
      default:
        return value;
    }
  }

  Color _statusColor(String value) {
    switch (value) {
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
      case 'expired':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  bool _showPickupCountdown(String status) {
    return status == 'claimed' ||
        status == 'volunteer_assigned' ||
        status == 'available';
  }

  @override
  Widget build(BuildContext context) {
    final Stream<QuerySnapshot<Map<String, dynamic>>>? stream =
        _donationsStream;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My claimed donations'),
      ),
      body: stream == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Please return to the login screen and sign in again.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Unable to load claimed donations.\n\n'
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
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
                  return const _EmptyClaimedView();
                }

                donations.sort((first, second) {
                  final DateTime? firstDeadline = _readDateTime(
                    first.data()['pickupDeadline'],
                  );

                  final DateTime? secondDeadline = _readDateTime(
                    second.data()['pickupDeadline'],
                  );

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
                });

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: donations.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildSummaryCard(donations.length),
                      );
                    }

                    return _buildDonationCard(donations[index - 1]);
                  },
                );
              },
            ),
    );
  }

  Widget _buildSummaryCard(int claimedCount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFF356B4D)
                  .withValues(alpha: 0.12),
              child: const Icon(
                Icons.inventory_outlined,
                color: Color(0xFF356B4D),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Claimed donations',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$claimedCount donation(s) associated with your NGO',
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

    final String storage = _readText(
      donation['storageMethod'],
      'unknown',
    );

    final String status = _readText(
      donation['status'],
      'unknown',
    );

    final String allergens = _readText(
      donation['allergens'],
      'Not declared',
    );

    final int quantity = _readInt(donation['quantity']);
    final Color countdownColor = _countdownColor(deadline);

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
              label: _statusLabel(status),
              color: _statusColor(status),
            ),
            const SizedBox(height: 16),
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
            _InfoRow(
              icon: Icons.warning_amber_outlined,
              label: 'Allergens',
              value: allergens,
            ),
            if (_showPickupCountdown(status)) ...[
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
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openDonationDetails(document.id),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('View donation details'),
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

class _EmptyClaimedView extends StatelessWidget {
  const _EmptyClaimedView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_outlined,
              size: 76,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 20),
            Text(
              'No claimed donations',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Donations you claim from the NGO dashboard '
              'will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}