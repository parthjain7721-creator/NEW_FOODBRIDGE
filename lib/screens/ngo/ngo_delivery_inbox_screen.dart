import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../volunteer/volunteer_task_details_screen.dart';

class NgoDeliveryInboxScreen extends StatefulWidget {
  const NgoDeliveryInboxScreen({super.key});

  @override
  State<NgoDeliveryInboxScreen> createState() =>
      _NgoDeliveryInboxScreenState();
}

class _NgoDeliveryInboxScreenState
    extends State<NgoDeliveryInboxScreen> {
  StreamSubscription<User?>? _authSubscription;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _donationsStream;

  String? _uid;

  bool _isOpeningDetails = false;

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

    _donationsStream = uid == null
        ? null
        : FirebaseFirestore.instance
            .collection('donations')
            .where('claimedByNgoId', isEqualTo: uid)
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
    if (value is num && value.isFinite && value > 0) {
      return '$value portions/packets';
    }

    return 'Quantity not recorded';
  }

  Future<void> _openDetails(String donationId) async {
    if (_isOpeningDetails) {
      return;
    }

    if (_uid == null ||
        FirebaseAuth.instance.currentUser?.uid != _uid) {
      return;
    }

    setState(() {
      _isOpeningDetails = true;
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
          _isOpeningDetails = false;
        });
      }
    }
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

  Widget _deliveryList({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
    required String status,
    required String emptyMessage,
  }) {
    final matchingDocuments = documents
        .where((document) => document.data()['status'] == status)
        .toList();

    final String dateField;

    switch (status) {
      case 'accepted':
        dateField = 'acceptedAt';
        break;
      case 'rejected':
        dateField = 'rejectedAt';
        break;
      default:
        dateField = 'deliveredAt';
    }

    matchingDocuments.sort((first, second) {
      final firstTime =
          _date(first.data()[dateField])?.millisecondsSinceEpoch ?? 0;

      final secondTime =
          _date(second.data()[dateField])?.millisecondsSinceEpoch ?? 0;

      final comparison = secondTime.compareTo(firstTime);

      return comparison != 0
          ? comparison
          : first.id.compareTo(second.id);
    });

    if (matchingDocuments.isEmpty) {
      return _message(emptyMessage);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: matchingDocuments.length,
      itemBuilder: (context, index) {
        final document = matchingDocuments[index];
        final data = document.data();

        final Color statusColor;
        final String statusLabel;

        switch (status) {
          case 'accepted':
            statusColor = Colors.green.shade700;
            statusLabel = 'Accepted by NGO';
            break;
          case 'rejected':
            statusColor = Colors.red.shade700;
            statusLabel = 'Rejected by NGO';
            break;
          default:
            statusColor = Colors.orange.shade900;
            statusLabel = 'Awaiting NGO review';
        }

        return Card(
          key: ValueKey(document.id),
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(20),
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
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text('Donation ID: ${document.id}'),
                const SizedBox(height: 6),
                Text(
                  'Delivery recorded: '
                  '${_formatDate(data['deliveredAt'])}',
                ),
                if (status != 'delivered') ...[
                  const SizedBox(height: 6),
                  Text(
                    'Decision recorded: '
                    '${_formatDate(data[dateField])}',
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isOpeningDetails
                        ? null
                        : () => _openDetails(document.id),
                    icon: Icon(
                      status == 'delivered'
                          ? Icons.fact_check_outlined
                          : Icons.receipt_long_outlined,
                    ),
                    label: Text(
                      status == 'delivered'
                          ? 'Review delivery'
                          : 'View delivery record',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('NGO delivery inbox'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'To review'),
              Tab(text: 'Accepted'),
              Tab(text: 'Rejected'),
            ],
          ),
        ),
        body: _uid == null
            ? _message(
                'Please log in with your NGO account to view deliveries.',
              )
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                key: ValueKey('ngo-deliveries-$_uid'),
                stream: _donationsStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Unable to load deliveries. '
                              'Check your connection and NGO account access.',
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

                  final documents = snapshot.data!.docs;

                  return TabBarView(
                    children: [
                      _deliveryList(
                        documents: documents,
                        status: 'delivered',
                        emptyMessage:
                            'No deliveries are awaiting review.\n\n'
                            'A donation appears here after the volunteer '
                            'records delivery handover to your NGO.',
                      ),
                      _deliveryList(
                        documents: documents,
                        status: 'accepted',
                        emptyMessage:
                            'Your NGO has no accepted deliveries yet.',
                      ),
                      _deliveryList(
                        documents: documents,
                        status: 'rejected',
                        emptyMessage:
                            'Your NGO has no rejected deliveries.',
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}