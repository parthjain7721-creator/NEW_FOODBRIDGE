import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../screens/ngo/donation_details_screen.dart';
import 'local_notification_store.dart';
import 'notification_service.dart';

class WorkflowNotificationService {
  WorkflowNotificationService._();

  static final WorkflowNotificationService instance =
      WorkflowNotificationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _activeUid;
  String? _activeRole;

  final Map<String, String> _lastDonationSignatures =
      <String, String>{};

  final Set<String> _knownAvailableDonationIds = <String>{};

  final Set<String> _knownOpportunityDonationIds = <String>{};

  bool _availableDonationsInitialized = false;

  bool _opportunityDonationsInitialized = false;

  final List<StreamSubscription<
      QuerySnapshot<Map<String, dynamic>>>> _subscriptions =
      <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

  bool _isStarted = false;

  Future<void> start({
    required String uid,
    required String role,
  }) async {
    if (_isStarted && _activeUid == uid && _activeRole == role) {
      return;
    }

    stop();

    _activeUid = uid;
    _activeRole = role;
    _isStarted = true;

    debugPrint(
      'WorkflowNotificationService: started for uid=$uid role=$role',
    );

    if (role == 'donor') {
      _startDonorNotifications(uid);
    } else if (role == 'ngo') {
      await _startNgoNotifications(uid);
    } else if (role == 'volunteer') {
      _startVolunteerNotifications(uid);
    }
  }

  void stop() {
    for (final StreamSubscription<
        QuerySnapshot<Map<String, dynamic>>> subscription
        in _subscriptions) {
      subscription.cancel();
    }

    _subscriptions.clear();

    _lastDonationSignatures.clear();
    _knownAvailableDonationIds.clear();
    _knownOpportunityDonationIds.clear();

    _availableDonationsInitialized = false;
    _opportunityDonationsInitialized = false;

    _activeUid = null;
    _activeRole = null;
    _isStarted = false;

    debugPrint(
      'WorkflowNotificationService: stopped.',
    );
  }

  void _startDonorNotifications(String uid) {
    final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
        subscription = _firestore
            .collection('donations')
            .where('donorId', isEqualTo: uid)
            .snapshots()
            .listen(
      (snapshot) {
        _handleDonationSnapshot(
          snapshot: snapshot,
          role: 'donor',
          uid: uid,
        );
      },
      onError: (error, stackTrace) {
        debugPrint(
          'Donor workflow notification listener failed: $error',
        );

        debugPrintStack(stackTrace: stackTrace);
      },
    );

    _subscriptions.add(subscription);
  }

  Future<void> _startNgoNotifications(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> profileSnapshot =
        await _firestore.collection('users').doc(uid).get();

    final Map<String, dynamic>? profile = profileSnapshot.data();

    final Object? rawSettings = profile?['ngoReceivingProfile'];
    final Map<String, dynamic>? settings =
        rawSettings is Map<String, dynamic> ? rawSettings : null;

    final Object? rawCategories =
        settings?['preferredFoodCategories'];

    final Set<String> preferredCategories =
        rawCategories is List
            ? rawCategories
                .whereType<String>()
                .toSet()
            : <String>{};

    final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
        availableSubscription = _firestore
            .collection('donations')
            .where('status', isEqualTo: 'available')
            .snapshots()
            .listen(
      (snapshot) {
        _handleAvailableDonations(
          snapshot: snapshot,
          uid: uid,
          preferredCategories: preferredCategories,
        );
      },
      onError: (error, stackTrace) {
        debugPrint(
          'NGO available-donation notification listener failed: '
          '$error',
        );

        debugPrintStack(stackTrace: stackTrace);
      },
    );

    final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
        claimedSubscription = _firestore
            .collection('donations')
            .where('claimedByNgoId', isEqualTo: uid)
            .snapshots()
            .listen(
      (snapshot) {
        _handleDonationSnapshot(
          snapshot: snapshot,
          role: 'ngo',
          uid: uid,
        );
      },
      onError: (error, stackTrace) {
        debugPrint(
          'NGO claimed-donation notification listener failed: '
          '$error',
        );

        debugPrintStack(stackTrace: stackTrace);
      },
    );

    _subscriptions.add(availableSubscription);
    _subscriptions.add(claimedSubscription);
  }

  void _startVolunteerNotifications(String uid) {
    final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
        opportunitySubscription = _firestore
            .collection('donations')
            .where('status', isEqualTo: 'claimed')
            .where('ngoPickupConfirmed', isEqualTo: true)
            .where('donorPickupConfirmed', isEqualTo: true)
            .snapshots()
            .listen(
      (snapshot) {
        _handlePickupOpportunities(
          snapshot: snapshot,
          uid: uid,
        );
      },
      onError: (error, stackTrace) {
        debugPrint(
          'Volunteer opportunity notification listener failed: '
          '$error',
        );

        debugPrintStack(stackTrace: stackTrace);
      },
    );

    final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
        assignedSubscription = _firestore
            .collection('donations')
            .where('assignedVolunteerId', isEqualTo: uid)
            .snapshots()
            .listen(
      (snapshot) {
        _handleDonationSnapshot(
          snapshot: snapshot,
          role: 'volunteer',
          uid: uid,
        );
      },
      onError: (error, stackTrace) {
        debugPrint(
          'Volunteer assigned-task notification listener failed: '
          '$error',
        );

        debugPrintStack(stackTrace: stackTrace);
      },
    );

    _subscriptions.add(opportunitySubscription);
    _subscriptions.add(assignedSubscription);
  }

  void _handleDonationSnapshot({
    required QuerySnapshot<Map<String, dynamic>> snapshot,
    required String role,
    required String uid,
  }) {
    if (_auth.currentUser?.uid != uid) {
      return;
    }

    for (final QueryDocumentSnapshot<Map<String, dynamic>> document
        in snapshot.docs) {
      final Map<String, dynamic> donation = document.data();

      final String signature = _donationSignature(donation);

      final String? previousSignature =
          _lastDonationSignatures[document.id];

      _lastDonationSignatures[document.id] = signature;

      if (previousSignature == null) {
        continue;
      }

      if (previousSignature == signature) {
        continue;
      }

      final NotificationPayload? payload = _buildWorkflowPayload(
        role: role,
        uid: uid,
        donation: donation,
      );

      if (payload != null) {
        unawaited(_showInAppNotification(payload));
      }
    }
  }

  void _handleAvailableDonations({
    required QuerySnapshot<Map<String, dynamic>> snapshot,
    required String uid,
    required Set<String> preferredCategories,
  }) {
    if (_auth.currentUser?.uid != uid) {
      return;
    }

    if (!_availableDonationsInitialized) {
      for (final QueryDocumentSnapshot<Map<String, dynamic>> document
          in snapshot.docs) {
        _knownAvailableDonationIds.add(document.id);
      }

      _availableDonationsInitialized = true;

      return;
    }

    for (final QueryDocumentSnapshot<Map<String, dynamic>> document
        in snapshot.docs) {
      final String donationId = document.id;

      if (_knownAvailableDonationIds.contains(donationId)) {
        continue;
      }

      _knownAvailableDonationIds.add(donationId);

      final Map<String, dynamic> donation = document.data();

      final String? foodCategory =
          donation['foodCategory'] as String?;

      final String eligibility =
          donation['eligibilityStatus'] as String? ?? '';

      final String donorId =
          donation['donorId'] as String? ?? '';

      final bool isEligible =
          eligibility == 'eligible' || eligibility == 'urgent';

      final bool matchesPreference =
          foodCategory != null &&
              preferredCategories.contains(foodCategory);

      final bool isNotOwnDonation = donorId != uid;

      if (!isEligible || !matchesPreference || !isNotOwnDonation) {
        continue;
      }

      unawaited(
        _showInAppNotification(
          NotificationPayload(
            title: 'New food donation available',
            body: 'A $foodCategory donation is available. '
                'Open it to review the details and claim it.',
            donationId: donationId,
          ),
        ),
      );
    }
  }

  void _handlePickupOpportunities({
    required QuerySnapshot<Map<String, dynamic>> snapshot,
    required String uid,
  }) {
    if (_auth.currentUser?.uid != uid) {
      return;
    }

    if (!_opportunityDonationsInitialized) {
      for (final QueryDocumentSnapshot<Map<String, dynamic>> document
          in snapshot.docs) {
        _knownOpportunityDonationIds.add(document.id);
      }

      _opportunityDonationsInitialized = true;

      return;
    }

    for (final QueryDocumentSnapshot<Map<String, dynamic>> document
        in snapshot.docs) {
      final String donationId = document.id;

      if (_knownOpportunityDonationIds.contains(donationId)) {
        continue;
      }

      final Map<String, dynamic> donation = document.data();

      if (!_isValidPickupOpportunity(donation)) {
        continue;
      }

      _knownOpportunityDonationIds.add(donationId);

      unawaited(
        _showInAppNotification(
          NotificationPayload(
            title: 'New pickup opportunity',
            body: 'A ${donation['foodCategory'] ?? 'food'} donation '
                'needs a volunteer. Open Available pickups to '
                'review and accept it.',
            donationId: donationId,
          ),
        ),
      );
    }
  }

  bool _isValidPickupOpportunity(Map<String, dynamic> donation) {
    final Object? quantity = donation['quantity'];
    final Object? eligibility = donation['eligibilityStatus'];

    final Timestamp? deadline =
        donation['pickupDeadline'] as Timestamp?;

    final Timestamp? planned =
        donation['plannedPickupAt'] as Timestamp?;

    final DateTime now = DateTime.now();

    return donation['status'] == 'claimed' &&
        donation['volunteerAssignmentStatus'] == 'pending' &&
        donation['ngoPickupConfirmed'] == true &&
        donation['donorPickupConfirmed'] == true &&
        donation['ngoCapacityConfirmed'] == true &&
        donation['ngoDetailsReviewed'] == true &&
        (donation['claimedByNgoId'] as String? ?? '').isNotEmpty &&
        (donation['assignedVolunteerId'] as String? ?? '').isEmpty &&
        quantity is num &&
        quantity.isFinite &&
        quantity > 0 &&
        donation['ngoConfirmedQuantity'] == quantity &&
        (eligibility == 'eligible' || eligibility == 'urgent') &&
        deadline != null &&
        planned != null &&
        deadline.toDate().isAfter(now) &&
        planned.toDate().isAfter(now) &&
        planned.toDate().isBefore(deadline.toDate());
  }

  NotificationPayload? _buildWorkflowPayload({
    required String role,
    required String uid,
    required Map<String, dynamic> donation,
  }) {
    final String status = donation['status'] as String? ?? '';

    final bool ngoPickupConfirmed =
        donation['ngoPickupConfirmed'] == true;

    if (role == 'donor') {
      if (status == 'claimed') {
        return NotificationPayload(
          title: 'Your donation was claimed',
          body: 'An NGO claimed your donation. '
              'Review the pickup plan and confirm your availability.',
          donationId: donation['donationId'] as String? ?? '',
        );
      }

      if (ngoPickupConfirmed) {
        return NotificationPayload(
          title: 'Confirm pickup arrangement',
          body: 'The NGO confirmed its receiving capacity and '
              'proposed a pickup plan. Please confirm your '
              'pickup availability.',
          donationId: donation['donationId'] as String? ?? '',
        );
      }

      if (status == 'volunteer_assigned') {
        return NotificationPayload(
          title: 'Volunteer assigned',
          body: 'A volunteer accepted this pickup task. '
              'Open the donation for the latest status.',
          donationId: donation['donationId'] as String? ?? '',
        );
      }

      if (status == 'picked_up') {
        return NotificationPayload(
          title: 'Donation picked up',
          body: 'The volunteer collected the donation. '
              'It is now awaiting delivery.',
          donationId: donation['donationId'] as String? ?? '',
        );
      }

      if (status == 'accepted') {
        return NotificationPayload(
          title: 'Donation accepted',
          body: 'The receiving NGO accepted the delivered donation.',
          donationId: donation['donationId'] as String? ?? '',
        );
      }

      if (status == 'rejected') {
        return NotificationPayload(
          title: 'Donation rejected',
          body: 'The receiving NGO rejected the delivered donation. '
              'Open the donation for details.',
          donationId: donation['donationId'] as String? ?? '',
        );
      }
    }

    if (role == 'ngo') {
      if (status == 'volunteer_assigned') {
        return NotificationPayload(
          title: 'Volunteer assigned',
          body: 'A volunteer accepted this pickup task. '
              'Open the donation for the latest status.',
          donationId: donation['donationId'] as String? ?? '',
        );
      }

      if (status == 'picked_up') {
        return NotificationPayload(
          title: 'Donation picked up',
          body: 'The volunteer collected the donation. '
              'It is now awaiting delivery.',
          donationId: donation['donationId'] as String? ?? '',
        );
      }

      if (status == 'delivered') {
        return NotificationPayload(
          title: 'Donation delivered',
          body: 'A volunteer delivered this donation. '
              'Open the delivery inbox to accept or reject it.',
          donationId: donation['donationId'] as String? ?? '',
        );
      }
    }

    if (role == 'volunteer') {
      if (status == 'accepted') {
        return NotificationPayload(
          title: 'Donation accepted',
          body: 'The receiving NGO accepted the delivered donation.',
          donationId: donation['donationId'] as String? ?? '',
        );
      }

      if (status == 'rejected') {
        return NotificationPayload(
          title: 'Donation rejected',
          body: 'The receiving NGO rejected the delivered donation. '
              'Open the donation for details.',
          donationId: donation['donationId'] as String? ?? '',
        );
      }
    }

    return null;
  }

  String _donationSignature(Map<String, dynamic> donation) {
    return [
      donation['status'],
      donation['ngoPickupConfirmed'],
      donation['donorPickupConfirmed'],
      donation['ngoCapacityConfirmed'],
      donation['ngoDetailsReviewed'],
      donation['assignedVolunteerId'],
      donation['eligibilityStatus'],
    ].join('|');
  }

  Future<void> _showInAppNotification(
    NotificationPayload payload,
  ) async {
    final String? uid = _activeUid;

    if (uid == null || uid.isEmpty) {
      return;
    }

    final BuildContext? context =
        NotificationService.navigatorKey.currentContext;

    final String notificationId = _generateNotificationId(
      donationId: payload.donationId,
    );

    final AppNotification notification = AppNotification(
      id: notificationId,
      title: payload.title,
      body: payload.body,
      donationId: payload.donationId,
      createdAt: DateTime.now(),
      isRead: false,
    );

    try {
      await LocalNotificationStore.instance.addNotification(
        uid: uid,
        notification: notification,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to save workflow notification locally: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }

    if (context == null || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${payload.title}\n${payload.body}',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _openDonationDetails(
              payload.donationId,
            ),
          ),
        ),
      );
  }

  String _generateNotificationId({
    required String donationId,
  }) {
    final int timestamp = DateTime.now().microsecondsSinceEpoch;

    final String safeDonationId = donationId.trim().isEmpty
        ? 'none'
        : donationId.trim();

    return 'notif_${timestamp}_$safeDonationId';
  }

  void _openDonationDetails(String donationId) {
    if (donationId.trim().isEmpty) {
      return;
    }

    final NavigatorState? navigator =
        NotificationService.navigatorKey.currentState;

    if (navigator == null) {
      return;
    }

    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => DonationDetailsScreen(
          donationId: donationId.trim(),
        ),
      ),
    );
  }
}

class NotificationPayload {
  final String title;
  final String body;
  final String donationId;

  const NotificationPayload({
    required this.title,
    required this.body,
    required this.donationId,
  });
}