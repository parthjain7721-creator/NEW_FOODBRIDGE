import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
  void didUpdateWidget(covariant VolunteerTaskDetailsScreen oldWidget) {
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
                            onPressed: _retry,
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

                final String status = _text(data['status'], 'unknown');

                final DateTime? deadline = _date(
                  data['pickupDeadline'],
                );

                final DateTime? plannedPickup = _date(
                  data['plannedPickupAt'],
                );

                final bool awaitingPickup =
                    status == 'volunteer_assigned';

                final bool windowOpen =
                    deadline != null && deadline.isAfter(_now);

                final bool confirmationsComplete =
                    data['ngoPickupConfirmed'] == true &&
                    data['ngoCapacityConfirmed'] == true &&
                    data['donorPickupConfirmed'] == true;

                final bool ordinarilyEligible =
                    data['eligibilityStatus'] == 'eligible' ||
                    data['eligibilityStatus'] == 'urgent';

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
                          _formatDate(_date(data['volunteerAssignedAt'])),
                        ),
                      ],
                    ),

                    if (awaitingPickup) ...[
                      _notice(
                        _remaining(deadline),
                        windowOpen
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                      if (!windowOpen)
                        _notice(
                          'Do not proceed with collection: the pickup '
                          'window is closed or its deadline is missing.',
                          Colors.red.shade700,
                        ),
                      if (!confirmationsComplete || !ordinarilyEligible)
                        _notice(
                          'The required confirmations or eligibility '
                          'are incomplete. Do not proceed with collection.',
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
                          'NGO pickup plan',
                          data['ngoPickupConfirmed'] == true
                              ? 'Confirmed'
                              : 'Not confirmed',
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

                    _section(
                      'Pickup verification — next module',
                      [
                        const Text(
                          'Before pickup completion is enabled, '
                          'FoodBridge will require:\n\n'
                          '1. Donation Passport QR verification.\n'
                          '2. Packaging-condition inspection.\n'
                          '3. Timestamped pickup photo evidence.\n\n'
                          'This screen does not mark the food as '
                          'picked up or delivered.',
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