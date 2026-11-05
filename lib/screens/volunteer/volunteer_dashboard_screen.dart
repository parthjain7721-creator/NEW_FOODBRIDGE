import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VolunteerDashboardScreen extends StatefulWidget {
  const VolunteerDashboardScreen({super.key});

  @override
  State<VolunteerDashboardScreen> createState() =>
      _VolunteerDashboardScreenState();
}

class _VolunteerDashboardScreenState
    extends State<VolunteerDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _availableStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _assignedStream;

  Timer? _timer;
  DateTime _now = DateTime.now();

  String? _acceptingId;
  bool _isSigningOut = false;

  bool get _isBusy => _acceptingId != null || _isSigningOut;

  @override
  void initState() {
    super.initState();

    final String? uid = _auth.currentUser?.uid;

    if (uid != null) {
      _availableStream = _firestore
          .collection('donations')
          .where('status', isEqualTo: 'claimed')
          .where('ngoPickupConfirmed', isEqualTo: true)
          .where('donorPickupConfirmed', isEqualTo: true)
          .snapshots();

      _assignedStream = _firestore
          .collection('donations')
          .where('assignedVolunteerId', isEqualTo: uid)
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

  DateTime? _date(dynamic value) {
    return value is Timestamp ? value.toDate() : null;
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

  bool _validOpportunity(Map<String, dynamic> data) {
    final DateTime? deadline = _date(data['pickupDeadline']);
    final DateTime? planned = _date(data['plannedPickupAt']);
    final Object? eligibility = data['eligibilityStatus'];

    return data['status'] == 'claimed' &&
        data['ngoPickupConfirmed'] == true &&
        data['donorPickupConfirmed'] == true &&
        data['ngoCapacityConfirmed'] == true &&
        (eligibility == 'eligible' || eligibility == 'urgent') &&
        _text(data['assignedVolunteerId'], '').isEmpty &&
        deadline != null &&
        planned != null &&
        deadline.isAfter(_now) &&
        planned.isAfter(_now) &&
        planned.isBefore(deadline);
  }

  Future<void> _acceptTask(String donationId) async {
    if (_isBusy) {
      return;
    }

    final bool? approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Accept this pickup?'),
        content: const Text(
          'Accept only if you can collect the full donation '
          'at the planned time and before the pickup deadline.\n\n'
          'Location-based travel feasibility is not calculated yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Accept task'),
          ),
        ],
      ),
    );

    if (!mounted || approved != true || _isBusy) {
      return;
    }

    final User? user = _auth.currentUser;

    if (user == null) {
      _message('Please log in again.', isError: true);
      return;
    }

    setState(() {
      _acceptingId = donationId;
    });

    try {
      final donationRef =
          _firestore.collection('donations').doc(donationId);
      final profileRef = _firestore.collection('users').doc(user.uid);

      await _firestore.runTransaction((transaction) async {
        final profileSnapshot = await transaction.get(profileRef);
        final donationSnapshot = await transaction.get(donationRef);

        final Map<String, dynamic>? profile = profileSnapshot.data();
        final Map<String, dynamic>? data = donationSnapshot.data();

        if (_text(profile?['role'], '').toLowerCase() != 'volunteer' ||
            profile?['isActive'] == false) {
          throw StateError('An active volunteer profile is required.');
        }

        if (!donationSnapshot.exists || data == null) {
          throw StateError('This donation no longer exists.');
        }

        final DateTime now = DateTime.now();
        final DateTime? deadline = _date(data['pickupDeadline']);
        final DateTime? planned = _date(data['plannedPickupAt']);

        if (data['status'] != 'claimed' ||
            _text(data['assignedVolunteerId'], '').isNotEmpty ||
            data['volunteerAssignmentStatus'] != 'pending') {
          throw StateError(
            'This pickup is no longer available for assignment.',
          );
        }

        if (data['ngoPickupConfirmed'] != true ||
            data['donorPickupConfirmed'] != true ||
            data['ngoCapacityConfirmed'] != true ||
            data['ngoDetailsReviewed'] != true) {
          throw StateError(
            'Both parties must complete the required confirmations.',
          );
        }

        if (data['eligibilityStatus'] != 'eligible' &&
            data['eligibilityStatus'] != 'urgent') {
          throw StateError('This donation is not eligible for pickup.');
        }

        if (deadline == null ||
            planned == null ||
            !deadline.isAfter(now) ||
            !planned.isAfter(now) ||
            !planned.isBefore(deadline)) {
          throw StateError('The pickup plan is no longer valid.');
        }

        transaction.update(donationRef, {
          'status': 'volunteer_assigned',
          'assignedVolunteerId': user.uid,
          'volunteerAssignmentStatus': 'assigned',
          'volunteerAssignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) {
        return;
      }

      _message('Pickup accepted. Open the My tasks tab to view it.');
    } on FirebaseException catch (error) {
      debugPrint(
        'Volunteer assignment failed: '
        '${error.code} - ${error.message}',
      );

      if (!mounted) {
        return;
      }

      _message(
        'Unable to accept pickup. (${error.code})',
        isError: true,
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      _message(error.message.toString(), isError: true);
    } catch (error) {
      debugPrint('Unexpected assignment error: $error');

      if (!mounted) {
        return;
      }

      _message('Unable to accept pickup. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _acceptingId = null;
        });
      }
    }
  }

  Future<void> _logout() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      await _auth.signOut();
    } catch (error) {
      debugPrint('Volunteer logout failed: $error');

      if (mounted) {
        _message('Unable to sign out. Please try again.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  void _message(String message, {bool isError = false}) {
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Volunteer Dashboard'),
          actions: [
            IconButton(
              tooltip: 'Logout',
              onPressed: _isBusy ? null : _logout,
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.volunteer_activism_outlined),
                text: 'Available pickups',
              ),
              Tab(
                icon: Icon(Icons.local_shipping_outlined),
                text: 'My tasks',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildList(_availableStream, available: true),
            _buildList(_assignedStream, available: false),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    Stream<QuerySnapshot<Map<String, dynamic>>>? stream, {
    required bool available,
  }) {
    if (stream == null) {
      return const Center(child: Text('Please log in again.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load pickup tasks.\n\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final documents = snapshot.data!.docs.where((document) {
          return !available || _validOpportunity(document.data());
        }).toList();

        documents.sort((first, second) {
          final DateTime? a = _date(first.data()['pickupDeadline']);
          final DateTime? b = _date(second.data()['pickupDeadline']);

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

        if (documents.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                available
                    ? 'No valid pickup opportunities right now.\n\n'
                        'Both donor and NGO confirmations are required.'
                    : 'No tasks assigned to you yet.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return _buildCard(documents[index], available: available);
          },
        );
      },
    );
  }

  Widget _buildCard(
    QueryDocumentSnapshot<Map<String, dynamic>> document, {
    required bool available,
  }) {
    final Map<String, dynamic> data = document.data();
    final bool accepting = _acceptingId == document.id;
    final Object? quantity = data['quantity'];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _text(data['foodCategory'], 'Food donation'),
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
              'Planned pickup: ${_formatDate(_date(data['plannedPickupAt']))}',
            ),
            const SizedBox(height: 8),
            Text(
              'Pickup deadline: ${_formatDate(_date(data['pickupDeadline']))}',
            ),
            const SizedBox(height: 8),
            Text(
              'Storage: ${_text(data['storageMethod'], 'Unknown')}',
            ),
            const SizedBox(height: 8),
            Text(
              'Allergens: ${_text(data['allergens'], 'Not declared')}',
            ),
            const SizedBox(height: 16),
            if (available)
              ElevatedButton.icon(
                onPressed:
                    _isBusy ? null : () => _acceptTask(document.id),
                icon: accepting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  accepting ? 'Accepting...' : 'Accept pickup task',
                ),
              )
            else ...[
              Text(
                'Status: ${_text(data['status'], 'Unknown').replaceAll('_', ' ')}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pickup scanning, photo proof, and delivery actions '
                'will be added in the next module.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}