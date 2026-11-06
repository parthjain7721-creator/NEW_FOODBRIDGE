import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'pickup_evidence_service.dart';

class PickupCompletionService {
  final PickupEvidenceService _evidenceService =
      PickupEvidenceService();

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  // Reuse an uploaded object when retrying this draft during
  // the lifetime of this service instance.
  final Map<String, PickupEvidenceUpload> _uploadedDrafts = {};

  Future<void> completePickup({
    required String donationId,
    required String localPhotoPath,
    required String packagingCondition,
    required String notes,
  }) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      throw StateError('Please log in again.');
    }

    if (packagingCondition != 'sealed' &&
        packagingCondition != 'intact') {
      throw StateError(
        'This packaging inspection does not permit pickup completion.',
      );
    }

    if (notes.length > 500) {
      throw StateError('Inspection notes are too long.');
    }

    final String cacheKey = '$uid|$donationId|$localPhotoPath';

    PickupEvidenceUpload? upload = _uploadedDrafts[cacheKey];

    if (upload == null) {
      upload = await _evidenceService.uploadPickupPhoto(
        donationId: donationId,
        localPhotoPath: localPhotoPath,
      );

      _uploadedDrafts[cacheKey] = upload;
    }

    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError(
        'Your account changed. The pickup was not finalized.',
      );
    }

    final HttpsCallable callable =
        _functions.httpsCallable('completeDonationPickup');

    final result = await callable.call({
      'donationId': donationId,
      'photoPath': upload.storagePath,
      'packagingCondition': packagingCondition,
      'notes': notes,
    });

    final Object? response = result.data;

    if (response is! Map ||
        response['pickupRecorded'] != true ||
        response['donationId'] != donationId) {
      throw StateError(
        'The server did not confirm pickup completion.',
      );
    }
  }
}