import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';


class DeliveryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;


  Future<void> markDelivered({
    required String donationId,
    required String handoverNotes,
  }) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;


    if (uid == null || uid.isEmpty) {
      throw StateError('Please log in again.');
    }


    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(donationId)) {
      throw StateError('A valid donation ID is required.');
    }


    if (handoverNotes.length > 500) {
      throw StateError(
        'Handover notes must contain 500 characters or fewer.',
      );
    }


    final DocumentReference<Map<String, dynamic>> donationRef =
        _firestore.collection('donations').doc(donationId);


    await _firestore.runTransaction<void>((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await transaction.get(donationRef);


      final Map<String, dynamic>? donation = snapshot.data();


      if (donation == null) {
        throw StateError('This donation no longer exists.');
      }


      if (donation['assignedVolunteerId'] != uid) {
        throw StateError('This donation is not assigned to you.');
      }


      if (donation['status'] != 'picked_up') {
        throw StateError(
          'This donation is not awaiting delivery confirmation.',
        );
      }


      if (donation['pickupInspection'] == null) {
        throw StateError(
          'Pickup must be recorded before delivery can be confirmed.',
        );
      }


      transaction.update(donationRef, {
        'status': 'delivered',
        'deliveredAt': FieldValue.serverTimestamp(),
        'deliveryHandover': {
          'volunteerId': uid,
          'notes': handoverNotes.trim(),
          'confirmedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });


    debugPrint(
      'Delivery handover recorded for donation $donationId.',
    );
  }


  Future<void> reviewDelivery({
    required String donationId,
    required bool accepted,
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


    if (!accepted && trimmedReason.isEmpty) {
      throw StateError('A rejection reason is required.');
    }


    if (trimmedReason.length > 500) {
      throw StateError(
        'The review reason must contain 500 characters or fewer.',
      );
    }


    final DocumentReference<Map<String, dynamic>> donationRef =
        _firestore.collection('donations').doc(donationId);


    await _firestore.runTransaction<void>((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await transaction.get(donationRef);


      final Map<String, dynamic>? donation = snapshot.data();


      if (donation == null) {
        throw StateError('This donation no longer exists.');
      }


      if (donation['claimedByNgoId'] != uid) {
        throw StateError(
          'Only the receiving NGO can review this delivery.',
        );
      }


      if (donation['status'] != 'delivered') {
        throw StateError(
          'This donation is not awaiting NGO review.',
        );
      }


      if (donation['deliveryHandover'] == null) {
        throw StateError(
          'The volunteer has not recorded delivery handover.',
        );
      }


      final Map<String, dynamic> updates = {
        'updatedAt': FieldValue.serverTimestamp(),
      };


      if (accepted) {
        updates['status'] = 'accepted';
        updates['acceptedAt'] = FieldValue.serverTimestamp();
        updates['ngoDeliveryReview'] = {
          'ngoId': uid,
          'decision': 'accepted',
          'reason': trimmedReason,
          'reviewedAt': FieldValue.serverTimestamp(),
        };
      } else {
        updates['status'] = 'rejected';
        updates['rejectedAt'] = FieldValue.serverTimestamp();
        updates['ngoDeliveryReview'] = {
          'ngoId': uid,
          'decision': 'rejected',
          'reason': trimmedReason,
          'reviewedAt': FieldValue.serverTimestamp(),
        };
      }


      transaction.update(donationRef, updates);
    });


    debugPrint(
      'Delivery review recorded for donation $donationId: '
      '${accepted ? 'accepted' : 'rejected'}.',
    );
  }
}