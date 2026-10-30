import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NgoClaimedDonationsScreen extends StatefulWidget {
  const NgoClaimedDonationsScreen({super.key});

  @override
  State<NgoClaimedDonationsScreen> createState() =>
      _NgoClaimedDonationsScreenState();
}

class _NgoClaimedDonationsScreenState
    extends State<NgoClaimedDonationsScreen> {
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
      _claimedDonations() {
    final String? ngoId = _auth.currentUser?.uid;

    if (ngoId == null) {
      return const Stream.empty();
    }

    return _firestore
        .collection('donations')
        .where(
          'claimedByNgoId',
          isEqualTo: ngoId,
        )
        .snapshots();
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

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatRemainingTime(DateTime deadline) {
    final Duration remaining = deadline.difference(_now);

    if (remaining.isNegative) {
      return 'Rescue window closed';
    }

    final int hours = remaining.inHours;
    final int minutes = remaining.inMinutes.remainder(60);
    final int seconds = remaining.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m remaining';
    }

    return '${minutes}m ${seconds}s remaining';
  }

  Color _countdownColor(DateTime deadline) {
    final Duration remaining = deadline.difference(_now);

    if (remaining.isNegative) {
      return Colors.red.shade700;
    }

    if (remaining.inMinutes <= 30) {
      return Colors.orange.shade800;
    }

    return Colors.green.shade700;
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
        return Colors.green.shade700;
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
        title: const Text('My claimed donations'),
      ),
      body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: _claimedDonations(),
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
                  'Unable to load claimed donations.\n\n'
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final documents =
              snapshot.data?.docs ?? [];

          if (documents.isEmpty) {
            return const _EmptyClaimedView();
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSummaryCard(
                donations.length,
              ),
              const SizedBox(height: 16),
              ...donations.map(_buildDonationCard),
            ],
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
              backgroundColor:
                  const Color(0xFF356B4D)
                      .withValues(alpha: 0.12),
              child: const Icon(
                Icons.inventory_outlined,
                color: Color(0xFF356B4D),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Claimed donations',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$claimedCount donation(s) claimed by your NGO',
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

    final String status =
        donation['status'] as String? ?? 'claimed';

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
                  label: _statusLabel(status),
                  color: _statusColor(status),
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
                    color: _countdownColor(deadline),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatRemainingTime(deadline),
                      style: TextStyle(
                        color:
                            _countdownColor(deadline),
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
                onPressed: isExpired
                    ? null
                    : () {
                        _showMessage(
                          'Donation details screen will be added next.',
                          Colors.blue.shade700,
                        );
                      },
                icon: const Icon(
                  Icons.visibility_outlined,
                ),
                label: const Text(
                  'View donation details',
                ),
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
        maxWidth: 160,
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

class _EmptyClaimedView extends StatelessWidget {
  const _EmptyClaimedView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
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
              style: Theme.of(context)
                  .textTheme
                  .titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Donations you claim from the NGO dashboard '
              'will appear here.',
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