import 'package:cloud_firestore/cloud_firestore.dart';

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