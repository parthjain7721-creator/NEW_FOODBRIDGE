import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PickupCompletionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> completePickup({
    required String donationId,
    required String localPhotoPath,
    required String packagingCondition,
    required String notes,
  }) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid.isEmpty) {
      throw StateError('Please log in again.');
    }

    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(donationId)) {
      throw StateError('A valid donation ID is required.');
    }

    if (packagingCondition != 'sealed' &&
        packagingCondition != 'intact') {
      throw StateError(
        'This packaging inspection does not permit pickup completion.',
      );
    }

    if (notes.length > 500) {
      throw StateError(
        'Inspection notes must contain 500 characters or fewer.',
      );
    }

    final File photoFile = File(localPhotoPath);

    if (!await photoFile.exists()) {
      throw StateError(
        'The inspection photo is no longer available on this device.',
      );
    }

    final List<int> photoBytes = await photoFile.readAsBytes();

    if (photoBytes.isEmpty) {
      throw StateError('The inspection photo is empty.');
    }

    final String photoSha256 = sha256.convert(photoBytes).toString();

    final DocumentReference<Map<String, dynamic>> donationRef =
        _firestore.collection('donations').doc(donationId);

    final DocumentReference<Map<String, dynamic>> evidenceRef =
        _firestore.collection('pickupEvidence').doc(donationId);

    await _firestore.runTransaction<void>((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> donationSnapshot =
          await transaction.get(donationRef);

      final Map<String, dynamic>? donation = donationSnapshot.data();

      if (donation == null) {
        throw StateError('This donation no longer exists.');
      }

      if (donation['assignedVolunteerId'] != uid) {
        throw StateError('This donation is not assigned to you.');
      }

      if (donation['status'] != 'volunteer_assigned' ||
          donation['volunteerAssignmentStatus'] != 'assigned') {
        throw StateError('This task is not awaiting pickup.');
      }

      if (donation['ngoPickupConfirmed'] != true ||
          donation['ngoCapacityConfirmed'] != true ||
          donation['ngoDetailsReviewed'] != true ||
          donation['donorPickupConfirmed'] != true) {
        throw StateError(
          'Required donor and NGO confirmations are incomplete.',
        );
      }

      if (donation['eligibilityStatus'] != 'eligible' &&
          donation['eligibilityStatus'] != 'urgent') {
        throw StateError(
          'This donation is not eligible for ordinary pickup.',
        );
      }

      final Object? quantity = donation['quantity'];

      if (quantity is! num ||
          !quantity.isFinite ||
          quantity <= 0 ||
          donation['ngoConfirmedQuantity'] != quantity) {
        throw StateError(
          'The confirmed donation quantity is invalid.',
        );
      }

      final Object? deadline = donation['pickupDeadline'];

      if (deadline is! Timestamp ||
          !deadline.toDate().isAfter(DateTime.now())) {
        throw StateError('The pickup window has closed.');
      }

      // This check prevents duplicate pickup completion.
      // Because evidence creation and donation update occur in the
      // same transaction, an existing pickupInspection also proves
      // that the matching evidence document was created.
      if (donation['pickupInspection'] != null) {
        throw StateError(
          'A pickup inspection has already been recorded.',
        );
      }

      final Map<String, dynamic> pickupInspection = {
        'volunteerId': uid,
        'packagingCondition': packagingCondition,
        'notes': notes.trim(),
        'photoCaptured': true,
        'photoStoredRemotely': false,
        'photoSha256': photoSha256,
        'photoSizeBytes': photoBytes.length,
        'recordedAt': FieldValue.serverTimestamp(),
      };

      transaction.set(evidenceRef, {
        'donationId': donationId,
        'volunteerId': uid,
        'packagingCondition': packagingCondition,
        'notes': notes.trim(),
        'photoCaptured': true,
        'photoStoredRemotely': false,
        'photoSha256': photoSha256,
        'photoSizeBytes': photoBytes.length,
        'recordedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(donationRef, {
        'status': 'picked_up',
        'pickedUpAt': FieldValue.serverTimestamp(),
        'pickupInspection': pickupInspection,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    debugPrint(
      'Pickup evidence recorded for donation $donationId. '
      'Photo SHA-256: $photoSha256',
    );
  }
}