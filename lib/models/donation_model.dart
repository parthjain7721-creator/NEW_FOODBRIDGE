import 'package:cloud_firestore/cloud_firestore.dart';

class DonationModel {
  final String id;
  final String donorId;
  final String foodCategory;
  final String storageMethod;
  final int quantity;
  final String allergens;
  final DateTime preparedAt;
  final DateTime postedAt;
  final DateTime pickupDeadline;
  final String packagingState;
  final String eligibilityStatus;
  final String status;

  const DonationModel({
    required this.id,
    required this.donorId,
    required this.foodCategory,
    required this.storageMethod,
    required this.quantity,
    required this.allergens,
    required this.preparedAt,
    required this.postedAt,
    required this.pickupDeadline,
    required this.packagingState,
    required this.eligibilityStatus,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'donationId': id,
      'donorId': donorId,
      'foodCategory': foodCategory,
      'storageMethod': storageMethod,
      'quantity': quantity,
      'allergens': allergens,
      'preparedAt': Timestamp.fromDate(preparedAt),
      'postedAt': Timestamp.fromDate(postedAt),
      'pickupDeadline': Timestamp.fromDate(pickupDeadline),
      'packagingState': packagingState,
      'eligibilityStatus': eligibilityStatus,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory DonationModel.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    return DonationModel(
      id: id,
      donorId: map['donorId'] as String? ?? '',
      foodCategory: map['foodCategory'] as String? ?? '',
      storageMethod: map['storageMethod'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      allergens: map['allergens'] as String? ?? '',
      preparedAt: _readDate(map['preparedAt']),
      postedAt: _readDate(map['postedAt']),
      pickupDeadline: _readDate(map['pickupDeadline']),
      packagingState: map['packagingState'] as String? ?? '',
      eligibilityStatus: map['eligibilityStatus'] as String? ?? '',
      status: map['status'] as String? ?? '',
    );
  }

  static DateTime _readDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return DateTime.now();
  }
}