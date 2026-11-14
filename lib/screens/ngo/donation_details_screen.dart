import 'dart:async';


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


import '../../services/firestore_service.dart';
import 'ngo_pickup_confirmation_screen.dart';


class DonationDetailsScreen extends StatefulWidget {
  final String donationId;


  const DonationDetailsScreen({
    super.key,
    required this.donationId,
  });


  @override
  State<DonationDetailsScreen> createState() =>
      _DonationDetailsScreenState();
}


class _DonationDetailsScreenState
    extends State<DonationDetailsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestoreService = FirestoreService();


  late Stream<DocumentSnapshot<Map<String, dynamic>>> _donationStream;


  Timer? _countdownTimer;
  DateTime _now = DateTime.now();


  bool _isClaiming = false;
  bool _isReviewing = false;


  @override
  void initState() {
    super.initState();


    _connectDonation();


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
  void didUpdateWidget(covariant DonationDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);


    if (oldWidget.donationId != widget.donationId) {
      _connectDonation();
    }
  }


  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }


  void _connectDonation() {
    _donationStream = _firestore
        .collection('donations')
        .doc(widget.donationId)
        .snapshots();
  }


  void _retry() {
    setState(() {
      _connectDonation();
    });
  }


  Future<void> _claimDonation() async {
    if (_isClaiming) {
      return;
    }


    final User? user = _auth.currentUser;


    if (user == null) {
      _showMessage(
        'Your session has ended. Please log in again.',
        Colors.red.shade700,
      );
      return;
    }


    setState(() {
      _isClaiming = true;
    });


    try {
      final donationRef =
          _firestore.collection('donations').doc(widget.donationId);


      final profileRef = _firestore.collection('users').doc(user.uid);


      await _firestore.runTransaction((transaction) async {
        final profileSnapshot = await transaction.get(profileRef);
        final donationSnapshot = await transaction.get(donationRef);


        final Map<String, dynamic>? profile = profileSnapshot.data();
        final String role = _readText(profile?['role'], '')
            .trim()
            .toLowerCase();


        if (role != 'ngo' || profile?['isActive'] == false) {
          throw StateError(
            'An active NGO profile is required to claim donations.',
          );
        }


        final Object? rawSettings = profile?['ngoReceivingProfile'];
        final Map<String, dynamic>? settings =
            rawSettings is Map<String, dynamic> ? rawSettings : null;


        final Object? receivingLocation = settings?['location'];
        final Object? rawReceivingAddress = settings?['address'];


        if (receivingLocation is! GeoPoint) {
          throw StateError(
            'Set your NGO receiving location before claiming donations.',
          );
        }


        final String receivingAddress =
            rawReceivingAddress is String &&
                    rawReceivingAddress.trim().isNotEmpty
                ? rawReceivingAddress.trim()
                : 'Receiving address not recorded';


        final Map<String, dynamic>? donation = donationSnapshot.data();


        if (!donationSnapshot.exists || donation == null) {
          throw StateError('This donation no longer exists.');
        }


        if (donation['donorId'] == user.uid) {
          throw StateError('You cannot claim your own donation.');
        }


        if (donation['status'] != 'available') {
          throw StateError(
            'This donation is no longer available for claiming.',
          );
        }


        final Object? eligibility = donation['eligibilityStatus'];


        if (eligibility != 'eligible' && eligibility != 'urgent') {
          throw StateError(
            'This donation is not eligible for an ordinary claim. '
            'Manual-review donations require a separate review process.',
          );
        }


        final Object? rawDeadline = donation['pickupDeadline'];


        if (rawDeadline is! Timestamp) {
          throw StateError(
            'The donation has no valid pickup deadline.',
          );
        }


        if (!rawDeadline.toDate().isAfter(DateTime.now())) {
          throw StateError('The Food Rescue Window has closed.');
        }


        transaction.update(donationRef, {
          'status': 'claimed',
          'claimedByNgoId': user.uid,
          'claimedAt': FieldValue.serverTimestamp(),
          'ngoPickupConfirmed': false,
          'volunteerAssignmentStatus': 'pending',
          'receivingLocation': receivingLocation,
          'receivingAddress': receivingAddress,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });


      if (!mounted) {
        return;
      }


      _showMessage(
        'Donation claimed. Next, confirm capacity and pickup time.',
        Colors.green.shade700,
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Donation claim failed: ${error.code} - ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);


      if (!mounted) {
        return;
      }


      _showMessage(
        'Unable to claim donation. (${error.code})',
        Colors.red.shade700,
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }


      _showMessage(
        error.message.toString(),
        Colors.red.shade700,
      );
    } catch (error, stackTrace) {
      debugPrint('Unexpected donation claim error: $error');
      debugPrintStack(stackTrace: stackTrace);


      if (!mounted) {
        return;
      }


      _showMessage(
        'Unable to claim donation. Please try again.',
        Colors.red.shade700,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isClaiming = false;
        });
      }
    }
  }


  Future<void> _reviewEligibility({
    required bool approved,
  }) async {
    if (_isReviewing) {
      return;
    }


    final User? user = _auth.currentUser;


    if (user == null) {
      _showMessage(
        'Your session has ended. Please log in again.',
        Colors.red.shade700,
      );
      return;
    }


    final TextEditingController reasonController =
        TextEditingController();


    final String? reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            approved
                ? 'Approve for redistribution'
                : 'Reject donation',
          ),
          content: TextField(
            controller: reasonController,
            maxLines: 3,
            maxLength: 500,
            autofocus: true,
            decoration: InputDecoration(
              labelText: approved
                  ? 'Review note (optional)'
                  : 'Rejection reason',
              hintText: approved
                  ? 'Optional NGO review note'
                  : 'Explain why this donation is not eligible',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final String reason =
                    reasonController.text.trim();


                if (!approved && reason.isEmpty) {
                  ScaffoldMessenger.of(dialogContext)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text(
                          'A rejection reason is required.',
                        ),
                      ),
                    );
                  return;
                }


                Navigator.of(dialogContext).pop(reason);
              },
              child: Text(
                approved ? 'Approve' : 'Reject',
              ),
            ),
          ],
        );
      },
    );


    if (!mounted || reason == null) {
      return;
    }


    setState(() {
      _isReviewing = true;
    });


    try {
      await _firestoreService.reviewManualEligibility(
        donationId: widget.donationId,
        approved: approved,
        reason: reason,
      );


      if (!mounted) {
        return;
      }


      _showMessage(
        approved
            ? 'Donation approved for redistribution.'
            : 'Donation rejected after manual review.',
        approved ? Colors.green.shade700 : Colors.red.shade700,
      );
    } on StateError catch (error) {
      if (mounted) {
        _showMessage(
          error.message.toString(),
          Colors.red.shade700,
        );
      }
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Manual eligibility review failed: '
        '${error.code} - ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);


      if (mounted) {
        _showMessage(
          error.code == 'permission-denied'
              ? 'Firestore denied the review. Check the published '
                  'security rules and your NGO profile.'
              : 'Unable to record the review. (${error.code})',
          Colors.red.shade700,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Manual eligibility review failed: $error');
      debugPrintStack(stackTrace: stackTrace);


      if (mounted) {
        _showMessage(
          'Unable to record the review. Please try again.',
          Colors.red.shade700,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isReviewing = false;
        });
      }
    }
  }


  void _openPickupConfirmation() {
    Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => NgoPickupConfirmationScreen(
          donationId: widget.donationId,
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


  String _quantityLabel(dynamic value) {
    if (value is num && value.isFinite && value > 0) {
      return '$value portions/packets';
    }


    return 'Not recorded';
  }


  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Not recorded';
    }


    final DateTime local = value.toLocal();


    String twoDigits(int number) {
      return number.toString().padLeft(2, '0');
    }


    return '${twoDigits(local.day)}/${twoDigits(local.month)}/'
        '${local.year} ${twoDigits(local.hour)}:'
        '${twoDigits(local.minute)}';
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


  String _packagingLabel(String value) {
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
        return value;
    }
  }


  String _eligibilityLabel(String value) {
    switch (value) {
      case 'eligible':
        return 'Eligible for pickup now';
      case 'urgent':
        return 'Urgent pickup required';
      case 'manual_review':
        return 'Needs manual NGO review';
      case 'not_eligible':
        return 'Not eligible for redistribution';
      default:
        return 'Unknown eligibility';
    }
  }


  String _statusLabel(String value) {
    switch (value) {
      case 'available':
        return 'Available';
      case 'claimed':
        return 'Claimed by NGO';
      case 'volunteer_assigned':
        return 'Volunteer assigned';
      case 'picked_up':
        return 'Picked up';
      case 'delivered':
        return 'Delivered';
      case 'accepted':
        return 'Accepted by NGO';
      case 'rejected':
        return 'Rejected by NGO';
      case 'expired':
        return 'Expired';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Unknown status';
    }
  }


  Color _statusColor(String value) {
    switch (value) {
      case 'available':
      case 'accepted':
        return Colors.green.shade700;
      case 'claimed':
        return Colors.blue.shade700;
      case 'volunteer_assigned':
        return Colors.indigo.shade700;
      case 'picked_up':
        return Colors.orange.shade800;
      case 'delivered':
        return Colors.teal.shade700;
      case 'rejected':
      case 'expired':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }


  String _volunteerLabel(Map<String, dynamic> donation) {
    final String status = _readText(donation['status'], 'unknown');
    final String assignment = _readText(
      donation['volunteerAssignmentStatus'],
      'pending',
    );
    final String volunteerId = _readText(
      donation['assignedVolunteerId'],
      '',
    );


    switch (status) {
      case 'picked_up':
        return 'Picked up by volunteer';
      case 'delivered':
        return 'Delivered to NGO';
      case 'accepted':
        return 'Delivery accepted by NGO';
      case 'rejected':
        return 'Donation rejected by NGO';
    }


    if (volunteerId.isNotEmpty || assignment == 'assigned') {
      return 'Volunteer assigned';
    }


    return 'Not assigned';
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
        title: const Text('Donation details'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _donationStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to load donation details.\n\n'
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
          final Map<String, dynamic>? donation = document.data();


          if (!document.exists || donation == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This donation no longer exists.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }


          final DateTime? deadline = _readDateTime(
            donation['pickupDeadline'],
          );


          final String status = _readText(
            donation['status'],
            'unknown',
          );


          final String eligibility = _readText(
            donation['eligibilityStatus'],
            'unknown',
          );


          final String claimant = _readText(
            donation['claimedByNgoId'],
            '',
          );


          final String donorId = _readText(
            donation['donorId'],
            '',
          );


          final String? currentUid = _auth.currentUser?.uid;


          final bool isClaimOwner =
              currentUid != null && claimant == currentUid;


          final bool windowOpen =
              deadline != null && deadline.isAfter(_now);


          final bool ordinarilyEligible =
              eligibility == 'eligible' || eligibility == 'urgent';


          final bool pickupConfirmed =
              donation['ngoPickupConfirmed'] == true;


          final bool canClaim =
              currentUid != null &&
              currentUid != donorId &&
              status == 'available' &&
              ordinarilyEligible &&
              windowOpen;


          final bool canConfirmPickup =
              isClaimOwner &&
              status == 'claimed' &&
              !pickupConfirmed &&
              ordinarilyEligible &&
              windowOpen;


          final bool canReview =
              currentUid != null &&
              currentUid != donorId &&
              status == 'available' &&
              eligibility == 'manual_review' &&
              windowOpen &&
              donation['ngoEligibilityReview'] == null;


          final Object? rawReview =
              donation['ngoEligibilityReview'];
          final Map<String, dynamic>? review =
              rawReview is Map<String, dynamic> ? rawReview : null;


          final bool showCountdown =
              status == 'available' ||
              status == 'claimed' ||
              status == 'volunteer_assigned';


          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _section(
                  title: _readText(
                    donation['foodCategory'],
                    'Food donation',
                  ),
                  icon: Icons.restaurant_outlined,
                  children: [
                    SelectableText('Donation ID: ${document.id}'),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _StatusChip(
                        label: _statusLabel(status),
                        color: _statusColor(status),
                      ),
                    ),
                  ],
                ),
                if (showCountdown) ...[
                  const SizedBox(height: 16),
                  _buildRescueWindowCard(deadline),
                ],
                const SizedBox(height: 16),
                _buildPassportCard(document.id, donation),
                const SizedBox(height: 16),
                if (canReview)
                  _section(
                    title: 'Manual NGO review',
                    icon: Icons.fact_check_outlined,
                    children: [
                      const Text(
                        'Review the declared food details and decide '
                        'whether this donation may enter the ordinary '
                        'redistribution workflow. Approval does not '
                        'change the pickup deadline.',
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isReviewing
                                  ? null
                                  : () => _reviewEligibility(
                                        approved: false,
                                      ),
                              icon: const Icon(Icons.close),
                              label: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isReviewing
                                  ? null
                                  : () => _reviewEligibility(
                                        approved: true,
                                      ),
                              icon: _isReviewing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check),
                              label: Text(
                                _isReviewing
                                    ? 'Saving...'
                                    : 'Approve',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                if (review != null)
                  _section(
                    title: 'Manual review record',
                    icon: Icons.history,
                    children: [
                      _InfoRow(
                        label: 'Decision',
                        value: _readText(
                          review['decision'],
                          'Not recorded',
                        ),
                      ),
                      _InfoRow(
                        label: 'Reviewing NGO',
                        value: _readText(
                          review['ngoId'],
                          'Not recorded',
                        ),
                      ),
                      _InfoRow(
                        label: 'Review note / reason',
                        value: _readText(
                          review['reason'],
                          'Not recorded',
                        ),
                      ),
                      _InfoRow(
                        label: 'Reviewed at',
                        value: _formatDateTime(
                          _readDateTime(review['reviewedAt']),
                        ),
                      ),
                    ],
                  ),
                _buildClaimCard(donation),
                const SizedBox(height: 16),
                if (canConfirmPickup)
                  ElevatedButton.icon(
                    onPressed: _openPickupConfirmation,
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text(
                      'Confirm capacity and pickup time',
                    ),
                  ),
                if (canClaim)
                  ElevatedButton.icon(
                    onPressed: _isClaiming ? null : _claimDonation,
                    icon: _isClaiming
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.volunteer_activism_outlined,
                          ),
                    label: Text(
                      _isClaiming ? 'Claiming...' : 'Claim this donation',
                    ),
                  ),
                if (status == 'available' && !canClaim)
                  _notice(
                    !ordinarilyEligible
                        ? 'This donation requires review or is not '
                            'eligible for redistribution.'
                        : !windowOpen
                            ? 'A valid, open pickup window is required '
                                'before claiming.'
                            : 'Sign in with an eligible NGO account '
                                'to claim a donation from another donor.',
                  ),
                if (pickupConfirmed && status == 'claimed')
                  _notice(
                    'NGO pickup confirmation is recorded. '
                    'Donor confirmation and volunteer assignment '
                    'are separate steps. A closed pickup window '
                    'still prevents collection.',
                  ),
                const SizedBox(height: 16),
                const Text(
                  'FoodBridge displays redistribution eligibility based '
                  'on declarations and rules. It does not certify food '
                  'safety. Pickup inspection and final NGO acceptance '
                  'are still required.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }


  Widget _buildRescueWindowCard(DateTime? deadline) {
    final Color color = _countdownColor(deadline);


    return _section(
      title: 'Food Rescue Window',
      icon: Icons.timer_outlined,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatRemainingTime(deadline),
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text('Pickup deadline: ${_formatDateTime(deadline)}'),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildPassportCard(
    String donationId,
    Map<String, dynamic> donation,
  ) {
    final Object? declaration = donation['donorDeclaration'];


    return _section(
      title: 'Donation Passport',
      icon: Icons.badge_outlined,
      children: [
        _InfoRow(label: 'Donation ID', value: donationId),
        _InfoRow(
          label: 'Donor ID',
          value: _readText(donation['donorId'], 'Not recorded'),
        ),
        _InfoRow(
          label: 'Food category',
          value: _readText(donation['foodCategory'], 'Not recorded'),
        ),
        _InfoRow(
          label: 'Quantity',
          value: _quantityLabel(donation['quantity']),
        ),
        _InfoRow(
          label: 'Storage method',
          value: _storageLabel(
            _readText(donation['storageMethod'], 'unknown'),
          ),
        ),
        _InfoRow(
          label: 'Packaging',
          value: _packagingLabel(
            _readText(donation['packagingState'], 'Not recorded'),
          ),
        ),
        _InfoRow(
          label: 'Allergens',
          value: _readText(
            donation['allergens'],
            'Not declared — this does not mean allergen-free',
          ),
        ),
        _InfoRow(
          label: 'Prepared at',
          value: _formatDateTime(
            _readDateTime(donation['preparedAt']),
          ),
        ),
        _InfoRow(
          label: 'Posted at',
          value: _formatDateTime(
            _readDateTime(donation['postedAt']),
          ),
        ),
        _InfoRow(
          label: 'Pickup deadline',
          value: _formatDateTime(
            _readDateTime(donation['pickupDeadline']),
          ),
        ),
        _InfoRow(
          label: 'Eligibility',
          value: _eligibilityLabel(
            _readText(donation['eligibilityStatus'], 'unknown'),
          ),
        ),
        _InfoRow(
          label: 'Donor declaration',
          value: declaration is String && declaration.trim().isNotEmpty
              ? declaration.trim()
              : declaration == true
                  ? 'Donor confirmation recorded'
                  : declaration == false
                      ? 'Donor confirmation not given'
                      : 'No separate donor declaration recorded',
        ),
      ],
    );
  }


  Widget _buildClaimCard(Map<String, dynamic> donation) {
    final String claimant = _readText(
      donation['claimedByNgoId'],
      '',
    );


    if (claimant.isEmpty) {
      return _section(
        title: 'NGO claim information',
        icon: Icons.home_work_outlined,
        children: [
          const Text('This donation has not been claimed yet.'),
        ],
      );
    }


    final bool confirmed = donation['ngoPickupConfirmed'] == true;


    return _section(
      title: 'NGO claim information',
      icon: Icons.home_work_outlined,
      children: [
        _InfoRow(label: 'Claimed by NGO', value: claimant),
        _InfoRow(
          label: 'Claimed at',
          value: _formatDateTime(
            _readDateTime(donation['claimedAt']),
          ),
        ),
        _InfoRow(
          label: 'Pickup confirmation',
          value: confirmed ? 'Confirmed' : 'Not confirmed',
        ),
        _InfoRow(
          label: 'Receiving capacity',
          value: donation['ngoCapacityConfirmed'] == true
              ? 'Confirmed'
              : 'Not confirmed',
        ),
        if (confirmed) ...[
          _InfoRow(
            label: 'Confirmed quantity',
            value: _quantityLabel(donation['ngoConfirmedQuantity']),
          ),
          _InfoRow(
            label: 'Planned pickup',
            value: _formatDateTime(
              _readDateTime(donation['plannedPickupAt']),
            ),
          ),
          _InfoRow(
            label: 'Confirmed at',
            value: _formatDateTime(
              _readDateTime(donation['ngoPickupConfirmedAt']),
            ),
          ),
        ],
        _InfoRow(
          label: 'Volunteer status',
          value: _volunteerLabel(donation),
        ),
      ],
    );
  }


  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: const Color(0xFF356B4D)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }


  Widget _notice(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message),
      ),
    );
  }
}


class _InfoRow extends StatelessWidget {
  final String label;
  final String value;


  const _InfoRow({
    required this.label,
    required this.value,
  });


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
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
        horizontal: 12,
        vertical: 7,
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
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}