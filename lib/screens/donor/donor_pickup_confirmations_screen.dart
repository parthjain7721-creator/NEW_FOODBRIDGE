import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DonorPickupConfirmationsScreen extends StatefulWidget {
  const DonorPickupConfirmationsScreen({super.key});

  @override
  State<DonorPickupConfirmationsScreen> createState() =>
      _DonorPickupConfirmationsScreenState();
}

class _DonorPickupConfirmationsScreenState
    extends State<DonorPickupConfirmationsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _donationsStream;

  Timer? _timer;
  DateTime _now = DateTime.now();
  String? _confirmingDonationId;

  @override
  void initState() {
    super.initState();

    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      // Query only by ownership to avoid requiring a composite index.
      _donationsStream = _firestore
          .collection('donations')
          .where('donorId', isEqualTo: uid)
          .snapshots();
    }

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
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  String _text(dynamic value, String fallback) {
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : fallback;
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

  String? _blockingReason(Map<String, dynamic> donation) {
    if (donation['status'] != 'claimed') {
      return 'This donation is no longer awaiting pickup confirmation.';
    }

    if (_text(donation['claimedByNgoId'], '').isEmpty) {
      return 'The NGO claim is missing.';
    }

    if (donation['ngoPickupConfirmed'] != true ||
        donation['ngoCapacityConfirmed'] != true) {
      return 'Waiting for the NGO to confirm capacity and pickup time.';
    }

    final Object? eligibility = donation['eligibilityStatus'];

    if (eligibility != 'eligible' && eligibility != 'urgent') {
      return 'This donation is not eligible for ordinary pickup.';
    }

    final DateTime? deadline = _readDate(
      donation['pickupDeadline'],
    );

    final DateTime? plannedPickup = _readDate(
      donation['plannedPickupAt'],
    );

    if (deadline == null || plannedPickup == null) {
      return 'A valid pickup deadline and planned pickup time are required.';
    }

    if (!deadline.isAfter(_now)) {
      return 'The pickup window has closed.';
    }

    if (!plannedPickup.isAfter(_now)) {
      return 'The planned pickup time has passed. '
          'The NGO pickup plan needs to be revised.';
    }

    if (!plannedPickup.isBefore(deadline)) {
      return 'The planned pickup is not before the deadline.';
    }

    return null;
  }

  Future<void> _confirmPickup(String donationId) async {
    if (_confirmingDonationId != null) {
      return;
    }

    final bool? approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm pickup arrangement?'),
        content: const Text(
          'Confirm that the donation is still available and that '
          'you can hand it over at the NGO’s planned pickup time.\n\n'
          'This does not certify food safety or assign a volunteer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (!mounted || approved != true) {
      return;
    }

    // A second invocation may have completed its dialog first.
    if (_confirmingDonationId != null) {
      return;
    }

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('Please log in again.', isError: true);
      return;
    }

    setState(() {
      _confirmingDonationId = donationId;
    });

    try {
      final donationRef =
          _firestore.collection('donations').doc(donationId);

      final profileRef = _firestore.collection('users').doc(user.uid);

      await _firestore.runTransaction((transaction) async {
        final profileSnapshot = await transaction.get(profileRef);
        final donationSnapshot = await transaction.get(donationRef);

        final Map<String, dynamic>? profile = profileSnapshot.data();

        if (_text(profile?['role'], '').toLowerCase() != 'donor' ||
            profile?['isActive'] == false) {
          throw StateError('An active donor profile is required.');
        }

        final Map<String, dynamic>? donation = donationSnapshot.data();

        if (!donationSnapshot.exists || donation == null) {
          throw StateError('This donation no longer exists.');
        }

        if (donation['donorId'] != user.uid) {
          throw StateError(
            'Only the donor who created this donation can confirm pickup.',
          );
        }

        if (donation['donorPickupConfirmed'] == true) {
          throw StateError('You have already confirmed this pickup.');
        }

        final DateTime now = DateTime.now();

        final Object? eligibility = donation['eligibilityStatus'];
        final Object? deadline = donation['pickupDeadline'];
        final Object? plannedPickup = donation['plannedPickupAt'];

        if (donation['status'] != 'claimed' ||
            _text(donation['claimedByNgoId'], '').isEmpty) {
          throw StateError('This donation has no active NGO claim.');
        }

        if (donation['ngoPickupConfirmed'] != true ||
            donation['ngoCapacityConfirmed'] != true) {
          throw StateError(
            'The NGO must confirm capacity and pickup time first.',
          );
        }

        if (eligibility != 'eligible' && eligibility != 'urgent') {
          throw StateError(
            'This donation is not eligible for ordinary pickup.',
          );
        }

        if (deadline is! Timestamp || plannedPickup is! Timestamp) {
          throw StateError('Valid pickup timestamps are required.');
        }

        if (!deadline.toDate().isAfter(now)) {
          throw StateError('The pickup window has closed.');
        }

        if (!plannedPickup.toDate().isAfter(now) ||
            !plannedPickup.toDate().isBefore(deadline.toDate())) {
          throw StateError(
            'The NGO needs to revise its planned pickup time.',
          );
        }

        transaction.update(donationRef, {
          'donorPickupConfirmed': true,
          'donorPickupConfirmedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) {
        return;
      }

      _showMessage(
        'Donor pickup confirmation saved. '
        'Volunteer assignment is the next step.',
      );
    } on FirebaseException catch (error) {
      debugPrint(
        'Donor pickup confirmation failed: '
        '${error.code} - ${error.message}',
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to save confirmation. (${error.code})',
        isError: true,
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.message.toString(), isError: true);
    } catch (error) {
      debugPrint('Unexpected donor confirmation error: $error');

      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to confirm pickup. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _confirmingDonationId = null;
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? Colors.red.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final stream = _donationsStream;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pickup confirmations'),
      ),
      body: stream == null
          ? const Center(
              child: Text('Please log in again.'),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Unable to load pickup confirmations.\n\n'
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

                final documents = snapshot.data!.docs.where((document) {
                  return document.data()['status'] == 'claimed';
                }).toList();

                if (documents.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No claimed donations awaiting pickup.\n\n'
                        'Donations claimed by an NGO will appear here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                documents.sort((first, second) {
                  final DateTime? a = _readDate(
                    first.data()['plannedPickupAt'],
                  );
                  final DateTime? b = _readDate(
                    second.data()['plannedPickupAt'],
                  );

                  if (a == null && b == null) {
                    return first.id.compareTo(second.id);
                  }

                  if (a == null) {
                    return 1;
                  }

                  if (b == null) {
                    return -1;
                  }

                  return a.compareTo(b);
                });

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    return _buildCard(documents[index]);
                  },
                );
              },
            ),
    );
  }

  Widget _buildCard(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final Map<String, dynamic> donation = document.data();

    final bool confirmed = donation['donorPickupConfirmed'] == true;
    final bool saving = _confirmingDonationId == document.id;
    final String? blockingReason = _blockingReason(donation);

    final bool canConfirm =
        !confirmed &&
        blockingReason == null &&
        _confirmingDonationId == null;

    final Object? quantity = donation['quantity'];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _text(donation['foodCategory'], 'Food donation'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SelectableText('Donation ID: ${document.id}'),
            const SizedBox(height: 8),
            Text(
              'Quantity: ${quantity is num ? quantity : 'Not recorded'}',
            ),
            const SizedBox(height: 8),
            Text(
              'Claiming NGO: '
              '${_text(donation['claimedByNgoId'], 'Not recorded')}',
            ),
            const SizedBox(height: 8),
            Text(
              'NGO capacity: '
              '${donation['ngoCapacityConfirmed'] == true ? 'Confirmed' : 'Not confirmed'}',
            ),
            const SizedBox(height: 8),
            Text(
              'Planned pickup: '
              '${_formatDate(_readDate(donation['plannedPickupAt']))}',
            ),
            const SizedBox(height: 8),
            Text(
              'Pickup deadline: '
              '${_formatDate(_readDate(donation['pickupDeadline']))}',
            ),
            const SizedBox(height: 16),
            if (confirmed)
              Text(
                blockingReason == null
                    ? 'Your confirmation is recorded. '
                        'Volunteer assignment has not been implemented yet.'
                    : 'Your confirmation is recorded, but the current '
                        'pickup plan needs attention: $blockingReason',
                style: TextStyle(
                  color: blockingReason == null
                      ? Colors.green.shade700
                      : Colors.orange.shade900,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (blockingReason != null)
              Text(
                blockingReason,
                style: TextStyle(color: Colors.orange.shade900),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed:
                  canConfirm ? () => _confirmPickup(document.id) : null,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                saving
                    ? 'Saving...'
                    : confirmed
                        ? 'Donor confirmation recorded'
                        : 'Confirm pickup arrangement',
              ),
            ),
          ],
        ),
      ),
    );
  }
}