import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';


import '../models/donation_model.dart';


class FirestoreService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;


  /*
   * USER PROFILE METHODS
   */
  Future<void> createUserProfile({
    required String uid,
    required String email,
    required String role,
    required String name,
    String phone = '',
    String organizationName = '',
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': email.trim(),
      'role': role.trim().toLowerCase(),
      'name': name.trim(),
      'phone': phone.trim(),
      'organizationName': organizationName.trim(),
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }


  Future<DocumentSnapshot<Map<String, dynamic>>> getUserProfile(
    String uid,
  ) {
    return _firestore.collection('users').doc(uid).get();
  }


  Future<void> updateUserProfile({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    await _firestore.collection('users').doc(uid).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }


  /*
   * DONATION METHODS
   */
  Future<String> createDonation(
    DonationModel donation,
  ) async {
    final DocumentReference<Map<String, dynamic>> document =
        _firestore.collection('donations').doc();


    final Map<String, dynamic> donationData = {
      ...donation.toMap(),
      'donationId': document.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };


    await document.set(donationData);


    return document.id;
  }


  Stream<QuerySnapshot<Map<String, dynamic>>>
      getAvailableDonations() {
    return _firestore
        .collection('donations')
        .where('status', isEqualTo: 'available')
        .snapshots();
  }


  Future<DocumentSnapshot<Map<String, dynamic>>> getDonation(
    String donationId,
  ) {
    return _firestore.collection('donations').doc(
          donationId,
        ).get();
  }


  /*
   * NGO CLAIM METHOD
   *
   * Uses a Firestore transaction to prevent two NGOs
   * from claiming the same donation at the same time.
   */
  Future<void> claimDonation({
    required String donationId,
    required String ngoId,
  }) async {
    final DocumentReference<Map<String, dynamic>> donationRef =
        _firestore.collection('donations').doc(donationId);


    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await transaction.get(donationRef);


      if (!snapshot.exists) {
        throw Exception('Donation no longer exists.');
      }


      final Map<String, dynamic>? donation = snapshot.data();


      if (donation == null) {
        throw Exception('Donation data is unavailable.');
      }


      final String currentStatus =
          donation['status'] as String? ?? 'unknown';


      if (currentStatus != 'available') {
        throw Exception(
          'This donation has already been claimed.',
        );
      }


      final Timestamp? deadline =
          donation['pickupDeadline'] as Timestamp?;


      if (deadline != null &&
          deadline.toDate().isBefore(DateTime.now())) {
        throw Exception(
          'The Food Rescue Window has closed.',
        );
      }


      transaction.update(donationRef, {
        'status': 'claimed',
        'claimedByNgoId': ngoId,
        'claimedAt': FieldValue.serverTimestamp(),
        'ngoPickupConfirmed': false,
        'volunteerAssignmentStatus': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }


  /*
   * NGO MANUAL ELIGIBILITY REVIEW
   *
   * Reviews an available donation that requires manual NGO review.
   * This does not claim the donation or change its pickup deadline.
   */
  Future<void> reviewManualEligibility({
    required String donationId,
    required bool approved,
    required String reason,
  }) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;


    if (uid == null || uid.isEmpty) {
      throw StateError('Please log in again.');
    }


    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(donationId)) {
      throw StateError('A valid donation ID is required.');
    }


    final String trimmedReason = reason.trim();


    if (!approved && trimmedReason.isEmpty) {
      throw StateError('A rejection reason is required.');
    }


    if (trimmedReason.length > 500) {
      throw StateError(
        'The review reason must contain 500 characters or fewer.',
      );
    }


    final DocumentReference<Map<String, dynamic>> donationRef =
        _firestore.collection('donations').doc(donationId);


    final DocumentReference<Map<String, dynamic>> profileRef =
        _firestore.collection('users').doc(uid);


    await _firestore.runTransaction<void>((transaction) async {
      final profileSnapshot = await transaction.get(profileRef);
      final donationSnapshot = await transaction.get(donationRef);


      final Map<String, dynamic>? profile = profileSnapshot.data();


      if (profile == null ||
          profile['role'] != 'ngo' ||
          profile['isActive'] == false) {
        throw StateError(
          'An active NGO profile is required to review donations.',
        );
      }


      final Map<String, dynamic>? donation = donationSnapshot.data();


      if (!donationSnapshot.exists || donation == null) {
        throw StateError('This donation no longer exists.');
      }


      if (donation['donorId'] == uid) {
        throw StateError('You cannot review your own donation.');
      }


      if (donation['status'] != 'available') {
        throw StateError(
          'Only available donations can be reviewed.',
        );
      }


      if (donation['eligibilityStatus'] != 'manual_review') {
        throw StateError(
          'This donation does not require manual NGO review.',
        );
      }


      if (donation['ngoEligibilityReview'] != null) {
        throw StateError(
          'This donation has already been reviewed.',
        );
      }


      final Object? rawDeadline = donation['pickupDeadline'];


      if (rawDeadline is! Timestamp) {
        throw StateError(
          'This donation has no valid pickup deadline.',
        );
      }


      final DateTime deadline = rawDeadline.toDate();
      final DateTime now = DateTime.now();


      if (!deadline.isAfter(now)) {
        throw StateError(
          'The Food Rescue Window has closed.',
        );
      }


      final int remainingMinutes =
          deadline.difference(now).inMinutes;


      final String approvedEligibility =
          remainingMinutes <= 60 ? 'urgent' : 'eligible';


      transaction.update(donationRef, {
        'eligibilityStatus':
            approved ? approvedEligibility : 'not_eligible',
        'ngoEligibilityReview': {
          'ngoId': uid,
          'decision': approved ? 'approved' : 'rejected',
          'reason': trimmedReason,
          'reviewedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }


  /*
   * FUTURE VOLUNTEER ASSIGNMENT METHOD
   */
  Future<void> assignVolunteer({
    required String donationId,
    required String volunteerId,
  }) async {
    final DocumentReference<Map<String, dynamic>> donationRef =
        _firestore.collection('donations').doc(donationId);


    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await transaction.get(donationRef);


      if (!snapshot.exists) {
        throw Exception('Donation no longer exists.');
      }


      final Map<String, dynamic>? donation = snapshot.data();


      if (donation == null) {
        throw Exception('Donation data is unavailable.');
      }


      final String currentStatus =
          donation['status'] as String? ?? 'unknown';


      if (currentStatus != 'claimed') {
        throw Exception(
          'Only claimed donations can be assigned to volunteers.',
        );
      }


      transaction.update(donationRef, {
        'assignedVolunteerId': volunteerId,
        'volunteerAssignmentStatus': 'assigned',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}