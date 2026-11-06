const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} =
  require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");

if (getApps().length === 0) {
  initializeApp();
}

exports.completeDonationPickup = onCall(
  {
    region: "us-central1",
    maxInstances: 5,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Please log in again.",
      );
    }

    const uid = request.auth.uid;
    const input = request.data || {};

    const donationId = input.donationId;
    const photoPath = input.photoPath;
    const packagingCondition = input.packagingCondition;
    const notes = input.notes === undefined ? "" : input.notes;

    if (
      typeof donationId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(donationId)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "A valid donation ID is required.",
      );
    }

    if (
      packagingCondition !== "sealed" &&
      packagingCondition !== "intact"
    ) {
      throw new HttpsError(
        "failed-precondition",
        "This packaging inspection does not permit pickup completion.",
      );
    }

    if (typeof notes !== "string" || notes.length > 500) {
      throw new HttpsError(
        "invalid-argument",
        "Inspection notes must contain no more than 500 characters.",
      );
    }

    const prefix = `pickupEvidence/${donationId}/${uid}/`;

    if (
      typeof photoPath !== "string" ||
      !photoPath.startsWith(prefix)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "The evidence path does not match this task and volunteer.",
      );
    }

    const fileName = photoPath.substring(prefix.length);

    if (!/^[A-Za-z0-9_-]+[.]jpg$/.test(fileName)) {
      throw new HttpsError(
        "invalid-argument",
        "The evidence filename is invalid.",
      );
    }

    const db = getFirestore();
    const donationRef = db.collection("donations").doc(donationId);
    const profileRef = db.collection("users").doc(uid);

    // Verify the caller before reading the evidence object.
    const profileSnapshot = await profileRef.get();
    const profile = profileSnapshot.data();

    if (
      !profile ||
      profile.role !== "volunteer" ||
      profile.isActive === false
    ) {
      throw new HttpsError(
        "permission-denied",
        "An active volunteer profile is required.",
      );
    }

    let metadata;

    try {
      // Uses the default Storage bucket for this Firebase project.
      [metadata] = await getStorage()
        .bucket()
        .file(photoPath)
        .getMetadata();
    } catch (error) {
      if (Number(error.code) === 404) {
        throw new HttpsError(
          "failed-precondition",
          "The pickup photo has not been uploaded.",
        );
      }

      console.error("Pickup evidence lookup failed", error);

      throw new HttpsError(
        "internal",
        "Unable to verify the uploaded photo.",
      );
    }

    const size = Number(metadata.size);
    const custom = metadata.metadata || {};

    if (
      !Number.isFinite(size) ||
      size <= 0 ||
      size > 5 * 1024 * 1024 ||
      metadata.contentType !== "image/jpeg" ||
      custom.donationId !== donationId ||
      custom.volunteerId !== uid ||
      custom.evidenceType !== "pickup_photo"
    ) {
      throw new HttpsError(
        "failed-precondition",
        "The uploaded evidence does not meet the required conditions.",
      );
    }

    const result = await db.runTransaction(async (transaction) => {
      const currentProfileSnapshot = await transaction.get(profileRef);
      const donationSnapshot = await transaction.get(donationRef);

      const currentProfile = currentProfileSnapshot.data();
      const donation = donationSnapshot.data();

      if (
        !currentProfile ||
        currentProfile.role !== "volunteer" ||
        currentProfile.isActive === false
      ) {
        throw new HttpsError(
          "permission-denied",
          "Your volunteer profile is not active.",
        );
      }

      if (!donation) {
        throw new HttpsError(
          "not-found",
          "This donation no longer exists.",
        );
      }

      if (donation.assignedVolunteerId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "This donation is not assigned to you.",
        );
      }

      // An identical retry must not create a second pickup.
      const previous = donation.pickupInspection;

      if (previous) {
        if (
          previous.volunteerId === uid &&
          previous.photoPath === photoPath
        ) {
          return {alreadyCompleted: true};
        }

        throw new HttpsError(
          "already-exists",
          "A pickup inspection has already been recorded.",
        );
      }

      if (
        donation.status !== "volunteer_assigned" ||
        donation.volunteerAssignmentStatus !== "assigned"
      ) {
        throw new HttpsError(
          "failed-precondition",
          "This task is not awaiting pickup.",
        );
      }

      if (
        donation.ngoPickupConfirmed !== true ||
        donation.ngoCapacityConfirmed !== true ||
        donation.ngoDetailsReviewed !== true ||
        donation.donorPickupConfirmed !== true
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Required pickup confirmations are incomplete.",
        );
      }

      if (
        donation.eligibilityStatus !== "eligible" &&
        donation.eligibilityStatus !== "urgent"
      ) {
        throw new HttpsError(
          "failed-precondition",
          "This donation is not eligible for ordinary pickup.",
        );
      }

      if (
        typeof donation.quantity !== "number" ||
        !Number.isFinite(donation.quantity) ||
        donation.quantity <= 0 ||
        donation.ngoConfirmedQuantity !== donation.quantity
      ) {
        throw new HttpsError(
          "failed-precondition",
          "The confirmed quantity is invalid.",
        );
      }

      const now = Timestamp.now();

      if (
        !(donation.pickupDeadline instanceof Timestamp) ||
        donation.pickupDeadline.toMillis() <= now.toMillis()
      ) {
        throw new HttpsError(
          "failed-precondition",
          "The pickup window has closed.",
        );
      }

      transaction.update(donationRef, {
        status: "picked_up",
        pickedUpAt: FieldValue.serverTimestamp(),
        pickupInspection: {
          volunteerId: uid,
          packagingCondition,
          notes: notes.trim(),
          photoPath,
          photoSizeBytes: size,
          photoGeneration: String(metadata.generation),
          recordedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {alreadyCompleted: false};
    });

    return {
      donationId,
      pickupRecorded: true,
      alreadyCompleted: result.alreadyCompleted,
    };
  },
);