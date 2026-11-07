import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DonorDonationHistoryScreen extends StatefulWidget {
  const DonorDonationHistoryScreen({super.key});

  @override
  State<DonorDonationHistoryScreen> createState() =>
      _DonorDonationHistoryScreenState();
}

class _DonorDonationHistoryScreenState
    extends State<DonorDonationHistoryScreen> {
  StreamSubscription<User?>? _authSubscription;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _donationsStream;

  String? _uid;
  String _filter = 'all';

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
            .where('donorId', isEqualTo: uid)
            .snapshots();
  }

  void _retry() {
    setState(() {
      _connect(FirebaseAuth.instance.currentUser?.uid);
    });
  }

  String _text(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return fallback;
  }

  Map<String, dynamic>? _map(dynamic value) {
    return value is Map<String, dynamic> ? value : null;
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

  String _statusLabel(String status) {
    switch (status) {
      case 'available':
        return 'Available';
      case 'claimed':
        return 'Claimed by NGO';
      case 'volunteer_assigned':
        return 'Volunteer assigned';
      case 'picked_up':
        return 'Picked up';
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
      case 'active':
        return const {
          'available',
          'claimed',
          'volunteer_assigned',
          'picked_up',
          'delivered',
        }.contains(status);

      case 'accepted':
        return status == 'accepted';

      case 'other_closed':
        return const {
          'rejected',
          'cancelled',
          'expired',
        }.contains(status);

      default:
        return true;
    }
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(value),
        ],
      ),
    );
  }

  Widget _event(String title, dynamic timestamp, Color color) {
    if (timestamp is! Timestamp) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(_formatDate(timestamp)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _donationCard(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final status = _text(data['status'], 'unknown');
    final review = _map(data['ngoDeliveryReview']);
    final handover = _map(data['deliveryHandover']);

    final Object? quantity = data['quantity'];

    final quantityLabel =
        quantity is num && quantity.isFinite && quantity > 0
            ? '$quantity portions/packets'
            : 'Quantity not recorded';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: PageStorageKey('${_uid}_${document.id}'),
        title: Text(
          _text(data['foodCategory'], 'Food donation'),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(quantityLabel),
              const SizedBox(height: 4),
              Text(
                _statusLabel(status),
                style: TextStyle(
                  color: _statusColor(status),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Posted: ${_formatDate(data['postedAt'])}',
              ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detail('Donation ID', document.id),
                _detail(
                  'Receiving NGO ID',
                  _text(data['claimedByNgoId'], 'Not yet claimed'),
                ),
                _detail(
                  'Assigned volunteer ID',
                  _text(
                    data['assignedVolunteerId'],
                    'Not yet assigned',
                  ),
                ),
                _detail(
                  'Pickup deadline',
                  _formatDate(data['pickupDeadline']),
                ),
                const SizedBox(height: 8),
                Text(
                  'Recorded progress',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                _event(
                  'Donation posted',
                  data['postedAt'],
                  Colors.blue.shade700,
                ),
                _event(
                  'Claimed by NGO',
                  data['claimedAt'],
                  Colors.blue.shade700,
                ),
                _event(
                  'NGO confirmed pickup arrangements',
                  data['ngoPickupConfirmedAt'],
                  Colors.blue.shade700,
                ),
                _event(
                  'Donor confirmed pickup arrangements',
                  data['donorPickupConfirmedAt'],
                  Colors.blue.shade700,
                ),
                _event(
                  'Volunteer assigned',
                  data['volunteerAssignedAt'],
                  Colors.blue.shade700,
                ),
                _event(
                  'Pickup recorded',
                  data['pickedUpAt'],
                  Colors.blue.shade700,
                ),
                _event(
                  'Volunteer recorded delivery handover',
                  data['deliveredAt'],
                  Colors.blue.shade700,
                ),
                _event(
                  'Delivery accepted by NGO',
                  data['acceptedAt'],
                  Colors.green.shade700,
                ),
                _event(
                  'Delivery rejected by NGO',
                  data['rejectedAt'],
                  Colors.red.shade700,
                ),
                if (handover != null)
                  _detail(
                    'Delivery handover notes',
                    _text(
                      handover['notes'],
                      'No handover notes recorded',
                    ),
                  ),
                if (review != null) ...[
                  _detail(
                    'NGO review decision',
                    _text(review['decision'], 'Not recorded'),
                  ),
                  _detail(
                    'NGO review reason or notes',
                    _text(
                      review['reason'],
                      'No reason or notes recorded',
                    ),
                  ),
                ],
                if (status == 'delivered')
                  const Text(
                    'The volunteer has recorded delivery. '
                    'The receiving NGO has not yet recorded '
                    'its final decision.',
                  ),
                const SizedBox(height: 12),
                const Text(
                  'This timeline displays saved workflow records. '
                  'It does not certify food safety.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
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
        title: const Text('My donation history'),
      ),
      body: _uid == null
          ? _message('Please log in to view your donation history.')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                    initialValue: _filter,
                    decoration: const InputDecoration(
                      labelText: 'Show donations',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('All donations'),
                      ),
                      DropdownMenuItem(
                        value: 'active',
                        child: Text('Active / awaiting completion'),
                      ),
                      DropdownMenuItem(
                        value: 'accepted',
                        child: Text('Accepted by NGO'),
                      ),
                      DropdownMenuItem(
                        value: 'other_closed',
                        child: Text('Rejected / cancelled / expired'),
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
                ),
                Expanded(
                  child: StreamBuilder<
                      QuerySnapshot<Map<String, dynamic>>>(
                    key: ValueKey(_uid),
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
                                  'Unable to load donation history. '
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

                      final documents = snapshot.data!.docs
                          .where(
                            (document) => _matchesFilter(
                              _text(
                                document.data()['status'],
                                'unknown',
                              ),
                            ),
                          )
                          .toList();

                      documents.sort((first, second) {
                        final firstDate =
                            _date(first.data()['postedAt']);
                        final secondDate =
                            _date(second.data()['postedAt']);

                        final comparison =
                            (secondDate?.millisecondsSinceEpoch ?? 0)
                                .compareTo(
                          firstDate?.millisecondsSinceEpoch ?? 0,
                        );

                        return comparison != 0
                            ? comparison
                            : first.id.compareTo(second.id);
                      });

                      if (documents.isEmpty) {
                        return _message(
                          _filter == 'all'
                              ? 'You have not posted any donations yet.'
                              : 'No donations match this filter.',
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          24,
                        ),
                        itemCount: documents.length,
                        itemBuilder: (context, index) {
                          return _donationCard(documents[index]);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}