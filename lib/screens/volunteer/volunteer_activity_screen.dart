import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'volunteer_task_details_screen.dart';

class VolunteerActivityScreen extends StatefulWidget {
  const VolunteerActivityScreen({super.key});

  @override
  State<VolunteerActivityScreen> createState() =>
      _VolunteerActivityScreenState();
}

class _VolunteerActivityScreenState
    extends State<VolunteerActivityScreen> {
  StreamSubscription<User?>? _authSubscription;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _tasksStream;

  String? _uid;
  String _filter = 'all';

  bool _isOpeningTask = false;

  @override
  void initState() {
    super.initState();

    _connect(FirebaseAuth.instance.currentUser?.uid);

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || user?.uid == _uid) {
        return;
      }

      setState(() {
        _filter = 'all';
        _connect(user?.uid);
      });
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _connect(String? uid) {
    _uid = uid;

    _tasksStream = uid == null
        ? null
        : FirebaseFirestore.instance
            .collection('donations')
            .where('assignedVolunteerId', isEqualTo: uid)
            .snapshots();
  }

  void _retry() {
    setState(() {
      _connect(FirebaseAuth.instance.currentUser?.uid);
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

  String _formatDate(dynamic value) {
    final date = _date(value)?.toLocal();

    if (date == null) {
      return 'Not recorded';
    }

    String two(int number) => number.toString().padLeft(2, '0');

    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String _quantity(dynamic value) {
    return value is num && value.isFinite && value > 0
        ? '$value portions/packets'
        : 'Quantity not recorded';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'volunteer_assigned':
        return 'Assigned — awaiting pickup';
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

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
        return Colors.green.shade700;
      case 'rejected':
      case 'cancelled':
      case 'expired':
        return Colors.red.shade700;
      case 'delivered':
        return Colors.orange.shade900;
      default:
        return Colors.blue.shade700;
    }
  }

  bool _matchesFilter(String status) {
    switch (_filter) {
      case 'in_progress':
        return status == 'volunteer_assigned' ||
            status == 'picked_up';
      case 'awaiting_review':
        return status == 'delivered';
      case 'accepted':
        return status == 'accepted';
      case 'rejected':
        return status == 'rejected';
      default:
        return true;
    }
  }

  Future<void> _openTask(String donationId) async {
    if (_isOpeningTask) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid != _uid) {
      return;
    }

    setState(() {
      _isOpeningTask = true;
    });

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => VolunteerTaskDetailsScreen(
            donationId: donationId,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningTask = false;
        });
      }
    }
  }

  Widget _metric(String label, int count) {
    return SizedBox(
      width: 150,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    int countStatus(String status) {
      return documents
          .where((document) => document.data()['status'] == status)
          .length;
    }

    final inProgress =
        countStatus('volunteer_assigned') + countStatus('picked_up');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your volunteer activity',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Based on donation records currently assigned '
          'to your account.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metric('Assigned tasks', documents.length),
            _metric('In progress', inProgress),
            _metric('Awaiting NGO review', countStatus('delivered')),
            _metric('Accepted deliveries', countStatus('accepted')),
            _metric('Rejected deliveries', countStatus('rejected')),
          ],
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: ValueKey('activity-filter-$_uid-$_filter'),
          initialValue: _filter,
          decoration: const InputDecoration(
            labelText: 'Show tasks',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'all',
              child: Text('All assigned tasks'),
            ),
            DropdownMenuItem(
              value: 'in_progress',
              child: Text('In progress'),
            ),
            DropdownMenuItem(
              value: 'awaiting_review',
              child: Text('Awaiting NGO review'),
            ),
            DropdownMenuItem(
              value: 'accepted',
              child: Text('Accepted deliveries'),
            ),
            DropdownMenuItem(
              value: 'rejected',
              child: Text('Rejected deliveries'),
            ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }

            setState(() {
              _filter = value;
            });
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _taskCard(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final status = _text(data['status'], 'unknown');

    return Card(
      key: ValueKey('activity-${document.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _text(data['foodCategory'], 'Food donation'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(_quantity(data['quantity'])),
            const SizedBox(height: 8),
            Text(
              _statusLabel(status),
              style: TextStyle(
                color: _statusColor(status),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text('Donation ID: ${document.id}'),
            const SizedBox(height: 6),
            Text(
              'Assigned: '
              '${_formatDate(data['volunteerAssignedAt'])}',
            ),
            if (data['deliveredAt'] is Timestamp) ...[
              const SizedBox(height: 6),
              Text(
                'Delivery recorded: '
                '${_formatDate(data['deliveredAt'])}',
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isOpeningTask
                    ? null
                    : () => _openTask(document.id),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('View task details'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String message) {
    return Center(
      child: Padding(
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('My volunteer activity'),
      ),
      body: _uid == null
          ? _message(
              'Please log in with your volunteer account.',
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              key: ValueKey('volunteer-activity-$_uid'),
              stream: _tasksStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Unable to load volunteer activity. '
                            'Check your connection and account access.',
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

                final allDocuments = snapshot.data!.docs;

                final filteredDocuments = allDocuments
                    .where(
                      (document) => _matchesFilter(
                        _text(document.data()['status'], 'unknown'),
                      ),
                    )
                    .toList();

                filteredDocuments.sort((first, second) {
                  final firstTime =
                      _date(first.data()['volunteerAssignedAt'])
                              ?.millisecondsSinceEpoch ??
                          0;

                  final secondTime =
                      _date(second.data()['volunteerAssignedAt'])
                              ?.millisecondsSinceEpoch ??
                          0;

                  final comparison = secondTime.compareTo(firstTime);

                  return comparison != 0
                      ? comparison
                      : first.id.compareTo(second.id);
                });

                final contentCount = filteredDocuments.isEmpty
                    ? 1
                    : filteredDocuments.length;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: contentCount + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _summary(allDocuments);
                    }

                    if (index == contentCount + 1) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Activity counts describe recorded workflow '
                          'outcomes. They do not verify meals served '
                          'or certify food safety.',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    if (filteredDocuments.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          allDocuments.isEmpty
                              ? 'No tasks are assigned to your account yet.'
                              : 'No tasks match this filter.',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    return _taskCard(
                      filteredDocuments[index - 1],
                    );
                  },
                );
              },
            ),
    );
  }
}