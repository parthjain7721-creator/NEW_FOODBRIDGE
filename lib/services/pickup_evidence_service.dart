import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class PickupEvidenceUpload {
  final String donationId;
  final String volunteerId;
  final String storagePath;
  final int sizeBytes;
  final DateTime? storageCreatedAt;

  const PickupEvidenceUpload({
    required this.donationId,
    required this.volunteerId,
    required this.storagePath,
    required this.sizeBytes,
    required this.storageCreatedAt,
  });
}

class PickupEvidenceService {
  static const int maxPhotoBytes = 5 * 1024 * 1024;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<PickupEvidenceUpload> uploadPickupPhoto({
    required String donationId,
    required String localPhotoPath,
  }) async {
    if (donationId.trim().isEmpty || donationId.contains('/')) {
      throw ArgumentError('A valid donation ID is required.');
    }

    if (localPhotoPath.trim().isEmpty) {
      throw ArgumentError('A pickup photo is required.');
    }

    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('Please log in again.');
    }

    final File file = File(localPhotoPath);

    if (!await file.exists()) {
      throw StateError(
        'The local photo is no longer available. Take another photo.',
      );
    }

    final int fileSize = await file.length();

    if (fileSize <= 0 || fileSize > maxPhotoBytes) {
      throw StateError(
        'The photo must be non-empty and no larger than 5 MiB.',
      );
    }

    final Uint8List bytes = await file.readAsBytes();

    if (bytes.isEmpty || bytes.length > maxPhotoBytes) {
      throw StateError('The photo size is invalid.');
    }

    // Basic JPEG signature check, not a full image-content validation.
    final bool looksLikeJpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;

    if (!looksLikeJpeg) {
      throw StateError(
        'This upload expects a JPEG photo. '
        'Please retake the photo using the Android camera.',
      );
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _firestore
            .collection('donations')
            .doc(donationId)
            .get(const GetOptions(source: Source.server));

    final Map<String, dynamic>? donation = snapshot.data();

    if (!snapshot.exists || donation == null) {
      throw StateError('This donation no longer exists.');
    }

    if (_auth.currentUser?.uid != user.uid) {
      throw StateError('Your account changed. Please try again.');
    }

    _validateTask(donation, user.uid);

    // Generates a random ID locally without writing a Firestore document.
    final String evidenceId =
        _firestore.collection('donations').doc().id;

    final String path =
        'pickupEvidence/$donationId/${user.uid}/$evidenceId.jpg';

    final Reference reference = _storage.ref().child(path);

    final TaskSnapshot uploaded = await reference.putData(
      bytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'donationId': donationId,
          'volunteerId': user.uid,
          'evidenceType': 'pickup_photo',
        },
      ),
    );

    return PickupEvidenceUpload(
      donationId: donationId,
      volunteerId: user.uid,
      storagePath: reference.fullPath,
      sizeBytes: uploaded.metadata?.size ?? bytes.length,
      storageCreatedAt: uploaded.metadata?.timeCreated,
    );
  }

  void _validateTask(
    Map<String, dynamic> donation,
    String volunteerId,
  ) {
    if (donation['assignedVolunteerId'] != volunteerId) {
      throw StateError('This task is not assigned to you.');
    }

    if (donation['status'] != 'volunteer_assigned' ||
        donation['volunteerAssignmentStatus'] != 'assigned') {
      throw StateError('This task is not currently awaiting pickup.');
    }

    if (donation['ngoPickupConfirmed'] != true ||
        donation['ngoCapacityConfirmed'] != true ||
        donation['ngoDetailsReviewed'] != true ||
        donation['donorPickupConfirmed'] != true) {
      throw StateError('Required pickup confirmations are incomplete.');
    }

    if (donation['eligibilityStatus'] != 'eligible' &&
        donation['eligibilityStatus'] != 'urgent') {
      throw StateError('The donation is not eligible for ordinary pickup.');
    }

    final Object? deadline = donation['pickupDeadline'];

    if (deadline is! Timestamp ||
        !deadline.toDate().isAfter(DateTime.now())) {
      throw StateError('The pickup window is closed or missing.');
    }

    final Object? quantity = donation['quantity'];

    if (quantity is! num ||
        !quantity.isFinite ||
        quantity <= 0 ||
        donation['ngoConfirmedQuantity'] != quantity) {
      throw StateError('The confirmed quantity is invalid.');
    }
  }
} 