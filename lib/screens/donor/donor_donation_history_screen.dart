import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/donation_receipt_service.dart';

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

  final Set<String> _expandedDonationIds = <String>{};

  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );

  final DonationReceiptService _receiptService =
      DonationReceiptService();

  String? _uid;
  String _filter = 'all';

  String? _generatingReceiptDonationId;

  bool get _isGeneratingReceipt =>
      _generatingReceiptDonationId != null;

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
        _expandedDonationIds.clear();
        _filter = 'all';
        _connect(user?.uid);
      });
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _scrollController.dispose();
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

  void _toggleDonation(String donationId) {
    setState(() {
      if (_expandedDonationIds.contains(donationId)) {
        _expandedDonationIds.remove(donationId);
      } else {
        _expandedDonationIds.add(donationId);
      }
    });
  }

  void _changeFilter(String? value) {
    if (value == null || value == _filter) {
      return;
    }

    setState(() {
      _filter = value;
      _expandedDonationIds.clear();
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _shareReceipt(String donationId) async {
    if (_isGeneratingReceipt) {
      return;
    }

    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid != _uid) {
      _showError(
        'Your account changed or your session ended. '
        'Please reopen donation history.',
      );
      return;
    }

    setState(() {
      _generatingReceiptDonationId = donationId;
    });

    try {
      await _receiptService.shareAcceptedDonationReceipt(
        donationId: donationId,
      );

      // Do not show a "saved successfully" message here.
      // Opening the share sheet does not confirm that the
      // user saved or sent the document.
    } catch (exception, stackTrace) {
      debugPrint('Receipt generation failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted ||
          FirebaseAuth.instance.currentUser?.uid != uid ||
          _uid != uid) {
        return;
      }

      final String message;

      if (exception is StateError) {
        message = exception.message.toString();
      } else if (exception is FirebaseException) {
        switch (exception.code) {
          case 'permission-denied':
            message =
                'Unable to read this donation. '
                'Check that it belongs to your signed-in donor account.';
            break;

          case 'unauthenticated':
            message =
                'Your session has ended. Please log in again.';
            break;

          case 'unavailable':
          case 'deadline-exceeded':
            message =
                'Unable to fetch the latest completion record. '
                'Check your connection and try again.';
            break;

          default:
            message =
                'Unable to read the completion record. '
                '(${exception.code})';
        }
      } else {
        message =
            'Unable to generate or share the receipt. '
            'Please try again.';
      }

      _showError(message);
    } finally {
      if (mounted) {
        setState(() {
          _generatingReceiptDonationId = null;
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
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
      padding: const EdgeInsets.only(bottom: 12),
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
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }

  Widget _event(
    String title,
    dynamic timestamp,
    Color color,
  ) {
    if (timestamp is! Timestamp) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
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
                const SizedBox(height: 4),
                Text(_formatDate(timestamp)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptSection(String donationId) {
    final bool isGeneratingThisReceipt =
        _generatingReceiptDonationId == donationId;

    return Padding(
      padding: const EdgeInsets.only(
        top: 8,
        bottom: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Donation completion receipt',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Generate a PDF summary of the accepted donation '
            'and its recorded workflow. The receipt is generated '
            'on your device and is not uploaded to Firebase Storage.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isGeneratingReceipt
                ? null
                : () => _shareReceipt(donationId),
            icon: isGeneratingThisReceipt
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(
              isGeneratingThisReceipt
                  ? 'Preparing receipt...'
                  : 'Share completion receipt',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This is a workflow receipt, not a food-safety '
            'certificate, carbon-impact certificate, or tax receipt.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _donationDetails(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final status = _text(data['status'], 'unknown');
    final handover = _map(data['deliveryHandover']);
    final review = _map(data['ngoDeliveryReview']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const SizedBox(height: 12),
          _detail('Donation ID', document.id),
          _detail(
            'Receiving NGO ID',
            _text(data['claimedByNgoId'], 'Not yet claimed'),
          ),
          _detail(
            'Assigned volunteer ID',
            _text(data['assignedVolunteerId'], 'Not yet assigned'),
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
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'The volunteer has recorded delivery. '
                'The receiving NGO has not yet recorded '
                'its final decision.',
              ),
            ),
          if (status == 'accepted')
            _receiptSection(document.id),
          const Text(
            'This timeline displays saved workflow records. '
            'It does not certify food safety.',
            style: TextStyle(fontSize: 12),
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
    final isExpanded = _expandedDonationIds.contains(document.id);

    final Object? quantity = data['quantity'];

    final quantityLabel =
        quantity is num && quantity.isFinite && quantity > 0
            ? '$quantity portions/packets'
            : 'Quantity not recorded';

    return Card(
      key: ValueKey('donation-$_uid-${document.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text(data['foodCategory'], 'Food donation'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(quantityLabel),
                const SizedBox(height: 6),
                Text(
                  _statusLabel(status),
                  style: TextStyle(
                    color: _statusColor(status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Posted: ${_formatDate(data['postedAt'])}',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _toggleDonation(document.id),
                  icon: Icon(
                    isExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                  label: Text(
                    isExpanded
                        ? 'Hide donation details'
                        : 'View donation details',
                  ),
                ),
              ],
            ),
          ),
          if (isExpanded) _donationDetails(document),
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
                    key: ValueKey('history-filter-$_uid-$_filter'),
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
                    onChanged: _changeFilter,
                  ),
                ),
                Expanded(
                  child: StreamBuilder<
                      QuerySnapshot<Map<String, dynamic>>>(
                    key: ValueKey('history-stream-$_uid'),
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
                        final firstTime =
                            _date(first.data()['postedAt'])
                                    ?.millisecondsSinceEpoch ??
                                0;

                        final secondTime =
                            _date(second.data()['postedAt'])
                                    ?.millisecondsSinceEpoch ??
                                0;

                        final comparison =
                            secondTime.compareTo(firstTime);

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
                        controller: _scrollController,
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