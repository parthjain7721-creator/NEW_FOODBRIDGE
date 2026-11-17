const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const {getApps, initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} =
  require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getStorage} = require("firebase-admin/storage");

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function isEligibleForPickup(donation) {
  return (
    donation.eligibilityStatus === "eligible" ||
    donation.eligibilityStatus === "urgent"
  );
}

function formatDateTime(timestamp) {
  if (!(timestamp instanceof Timestamp)) {
    return "the planned time";
  }

  return timestamp.toDate().toLocaleString("en-IN", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

async function sendToUser(userId, payload) {
  if (!isNonEmptyString(userId)) {
    return;
  }

  const tokensSnapshot = await db
    .collection("fcmTokens")
    .where("userId", "==", userId)
    .get();

  if (tokensSnapshot.empty) {
    console.log(`No FCM tokens found for user ${userId}.`);
    return;
  }

  const sendPromises = tokensSnapshot.docs.map(async (tokenDocument) => {
    const token = tokenDocument.data().token;

    if (!isNonEmptyString(token)) {
      return;
    }

    try {
      await getMessaging().send({
        token,
        notification: {
          title: payload.title,
          body: payload.body,
        },
        data: {
          type: payload.type,
          donationId: payload.donationId,
        },
        android: {
          priority: "high",
        },
      });

      console.log(
        `Notification sent to user ${userId} `
        + `using token ${tokenDocument.id}.`,
      );
    } catch (error) {
      if (
        error.errorInfo &&
        (
          error.errorInfo.code ===
            "messaging/registration-token-not-registered" ||
          error.errorInfo.code ===
            "messaging/invalid-registration-token"
        )
      ) {
        await tokenDocument.ref.delete();

        console.log(
          `Removed invalid FCM token ${tokenDocument.id} `
          + `for user ${userId}.`,
        );

        return;
      }

      console.error(
        `Failed to send notification to user ${userId}:`,
        error,
      );
    }
  });

  await Promise.allSettled(sendPromises);
}

async function sendToUsers(userIds, payload) {
  const uniqueUserIds = Array.from(
    new Set(
      userIds.filter(isNonEmptyString),
    ),
  );

  await Promise.allSettled(
    uniqueUserIds.map((userId) => sendToUser(userId, payload)),
  );
}

async function getActiveUserIdsByRole(role) {
  const snapshot = await db
    .collection("users")
    .where("role", "==", role)
    .where("isActive", "==", true)
    .get();

  return snapshot.docs
    .map((document) => document.id)
    .filter(isNonEmptyString);
}

async function getInterestedNgoIds(donation, donorId) {
  const foodCategory = donation.foodCategory;

  if (!isNonEmptyString(foodCategory)) {
    return [];
  }

  const ngoIds = await getActiveUserIdsByRole("ngo");

  if (ngoIds.length === 0) {
    return [];
  }

  const profileSnapshots = await Promise.all(
    ngoIds.map((ngoId) => db.collection("users").doc(ngoId).get()),
  );

  return profileSnapshots
    .filter((snapshot) => snapshot.exists)
    .filter((snapshot) => {
      const profile = snapshot.data();

      if (!profile || profile.id === donorId) {
        return false;
      }

      const receivingProfile = profile.ngoReceivingProfile;

      if (!receivingProfile || typeof receivingProfile !== "object") {
        return false;
      }

      const preferredCategories =
        receivingProfile.preferredFoodCategories;

      return (
        Array.isArray(preferredCategories) &&
        preferredCategories.includes(foodCategory)
      );
    })
    .map((snapshot) => snapshot.id);
}

/*
 * DONATION POSTED
 *
 * Notifies active NGOs whose preferred food categories include the
 * donation category. The donor is excluded.
 */
exports.onDonationCreated = onDocumentCreated(
  "donations/{donationId}",
  async (event) => {
    const snapshot = event.data;

    if (!snapshot) {
      return;
    }

    const donation = snapshot.data();
    const donationId = event.params.donationId;

    const isAvailable =
      donation.status === "available" &&
      isEligibleForPickup(donation);

    if (!isAvailable) {
      return;
    }

    const donorId = isNonEmptyString(donation.donorId)
      ? donation.donorId
      : "";

    const ngoIds = await getInterestedNgoIds(donation, donorId);

    await sendToUsers(ngoIds, {
      title: "New food donation available",
      body: `A ${donation.foodCategory || "food"} donation is available. `
        + "Open it to review the details and claim it.",
      type: "donation_posted",
      donationId,
    });
  },
);

/*
 * NGO CLAIMED DONATION
 *
 * Notifies the donor that an NGO has claimed the donation.
 */
exports.onDonationClaimed = onDocumentUpdated(
  "donations/{donationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    const donationId = event.params.donationId;

    const claimedNow =
      before.status !== "claimed" &&
      after.status === "claimed";

    if (!claimedNow) {
      return;
    }

    const donorId = isNonEmptyString(after.donorId)
      ? after.donorId
      : "";

    const ngoId = isNonEmptyString(after.claimedByNgoId)
      ? after.claimedByNgoId
      : "";

    await sendToUser(donorId, {
      title: "Your donation was claimed",
      body: "An NGO claimed your donation. "
        + "Review the pickup plan and confirm your availability.",
      type: "donation_claimed",
      donationId,
    });

    await sendToUser(ngoId, {
      title: "Donation claimed",
      body: "Confirm receiving capacity and the pickup plan "
        + "for this donation.",
      type: "donation_claimed",
      donationId,
    });
  },
);

/*
 * NGO CONFIRMED PICKUP PLAN
 *
 * Notifies the donor to confirm the pickup arrangement.
 */
exports.onNgoPickupConfirmed = onDocumentUpdated(
  "donations/{donationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    const donationId = event.params.donationId;

    const confirmedNow =
      before.ngoPickupConfirmed !== true &&
      after.ngoPickupConfirmed === true;

    if (!confirmedNow) {
      return;
    }

    const donorId = isNonEmptyString(after.donorId)
      ? after.donorId
      : "";

    await sendToUser(donorId, {
      title: "Confirm pickup arrangement",
      body: `The NGO proposed pickup at `
        + `${formatDateTime(after.plannedPickupAt)}. `
        + "Please confirm your pickup availability.",
      type: "ngo_pickup_confirmed",
      donationId,
    });
  },
);

/*
 * DONOR CONFIRMED PICKUP
 *
 * Notifies active volunteers that a fully confirmed pickup
 * opportunity is available.
 */
exports.onDonorPickupConfirmed = onDocumentUpdated(
  "donations/{donationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    const donationId = event.params.donationId;

    const confirmedNow =
      before.donorPickupConfirmed !== true &&
      after.donorPickupConfirmed === true;

    const opportunityReady =
      after.status === "claimed" &&
      after.ngoPickupConfirmed === true &&
      after.donorPickupConfirmed === true &&
      isEligibleForPickup(after);

    if (!confirmedNow || !opportunityReady) {
      return;
    }

    const volunteerIds = await getActiveUserIdsByRole("volunteer");

    await sendToUsers(volunteerIds, {
      title: "New pickup opportunity",
      body: `A ${after.foodCategory || "food"} donation needs a volunteer. `
        + "Open Available pickups to review and accept it.",
      type: "pickup_opportunity_available",
      donationId,
    });
  },
);

/*
 * VOLUNTEER ACCEPTED PICKUP
 *
 * Notifies the donor and claiming NGO.
 */
exports.onVolunteerAssigned = onDocumentUpdated(
  "donations/{donationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    const donationId = event.params.donationId;

    const assignedNow =
      before.status !== "volunteer_assigned" &&
      after.status === "volunteer_assigned";

    if (!assignedNow) {
      return;
    }

    const donorId = isNonEmptyString(after.donorId)
      ? after.donorId
      : "";

    const ngoId = isNonEmptyString(after.claimedByNgoId)
      ? after.claimedByNgoId
      : "";

    await sendToUsers([donorId, ngoId], {
      title: "Volunteer assigned",
      body: "A volunteer accepted this pickup task. "
        + "Open the donation for the latest status.",
      type: "volunteer_assigned",
      donationId,
    });
  },
);

/*
 * VOLUNTEER PICKED UP DONATION
 *
 * Notifies the donor and claiming NGO.
 */
exports.onDonationPickedUp = onDocumentUpdated(
  "donations/{donationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    const donationId = event.params.donationId;

    const pickedUpNow =
      before.status !== "picked_up" &&
      after.status === "picked_up";

    if (!pickedUpNow) {
      return;
    }

    const donorId = isNonEmptyString(after.donorId)
      ? after.donorId
      : "";

    const ngoId = isNonEmptyString(after.claimedByNgoId)
      ? after.claimedByNgoId
      : "";

    await sendToUsers([donorId, ngoId], {
      title: "Donation picked up",
      body: "The volunteer collected the donation. "
        + "It is now awaiting delivery.",
      type: "donation_picked_up",
      donationId,
    });
  },
);

/*
 * VOLUNTEER DELIVERED DONATION
 *
 * Notifies the claiming NGO for delivery review.
 */
exports.onDonationDelivered = onDocumentUpdated(
  "donations/{donationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    const donationId = event.params.donationId;

    const deliveredNow =
      before.status !== "delivered" &&
      after.status === "delivered";

    if (!deliveredNow) {
      return;
    }

    const ngoId = isNonEmptyString(after.claimedByNgoId)
      ? after.claimedByNgoId
      : "";

    await sendToUser(ngoId, {
      title: "Donation delivered",
      body: "A volunteer delivered this donation. "
        + "Open the delivery inbox to accept or reject it.",
      type: "donation_delivered",
      donationId,
    });
  },
);

/*
 * NGO ACCEPTED OR REJECTED DELIVERY
 *
 * Notifies the donor and assigned volunteer.
 */
exports.onDonationReviewed = onDocumentUpdated(
  "donations/{donationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    const donationId = event.params.donationId;

    const acceptedNow =
      before.status !== "accepted" &&
      after.status === "accepted";

    const rejectedNow =
      before.status !== "rejected" &&
      after.status === "rejected";

    if (!acceptedNow && !rejectedNow) {
      return;
    }

    const donorId = isNonEmptyString(after.donorId)
      ? after.donorId
      : "";

    const volunteerId = isNonEmptyString(after.assignedVolunteerId)
      ? after.assignedVolunteerId
      : "";

    await sendToUsers([donorId, volunteerId], {
      title: acceptedNow
        ? "Donation accepted"
        : "Donation rejected",
      body: acceptedNow
        ? "The receiving NGO accepted the delivered donation."
        : "The receiving NGO rejected the delivered donation. "
          + "Open the donation for details.",
      type: acceptedNow
        ? "donation_accepted"
        : "donation_rejected",
      donationId,
    });
  },
);

/*
 * DONATION CANCELLED OR EXPIRED
 *
 * Notifies the donor, claiming NGO, and assigned volunteer when relevant.
 */
exports.onDonationCancelledOrExpired = onDocumentUpdated(
  "donations/{donationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    const donationId = event.params.donationId;

    const cancelledNow =
      before.status !== "cancelled" &&
      after.status === "cancelled";

    const expiredNow =
      before.status !== "expired" &&
      after.status === "expired";

    if (!cancelledNow && !expiredNow) {
      return;
    }

    const donorId = isNonEmptyString(after.donorId)
      ? after.donorId
      : "";

    const ngoId = isNonEmptyString(after.claimedByNgoId)
      ? after.claimedByNgoId
      : "";

    const volunteerId = isNonEmptyString(after.assignedVolunteerId)
      ? after.assignedVolunteerId
      : "";

    await sendToUsers([donorId, ngoId, volunteerId], {
      title: cancelledNow
        ? "Donation cancelled"
        : "Donation expired",
      body: cancelledNow
        ? "This donation was cancelled. No further action is required."
        : "This donation expired before completion.",
      type: cancelledNow
        ? "donation_cancelled"
        : "donation_expired",
      donationId,
    });
  },
);

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