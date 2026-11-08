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

  final String pickupAddress;
  final String pickupCity;
  final GeoPoint? pickupLocation;

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
    this.pickupAddress = '',
    this.pickupCity = '',
    this.pickupLocation,
  });

  // Used after Firestore assigns the document ID.
  DonationModel withId(String donationId) {
    return DonationModel(
      id: donationId,
      donorId: donorId,
      foodCategory: foodCategory,
      storageMethod: storageMethod,
      quantity: quantity,
      allergens: allergens,
      preparedAt: preparedAt,
      postedAt: postedAt,
      pickupDeadline: pickupDeadline,
      packagingState: packagingState,
      eligibilityStatus: eligibilityStatus,
      status: status,
      pickupAddress: pickupAddress,
      pickupCity: pickupCity,
      pickupLocation: pickupLocation,
    );
  }

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
      if (pickupLocation != null) ...{
        'pickupAddress': pickupAddress.trim(),
        'pickupCity': pickupCity.trim(),
        'pickupLocation': pickupLocation,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory DonationModel.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    final Object? rawQuantity = map['quantity'];
    final Object? rawLocation = map['pickupLocation'];

    return DonationModel(
      id: id,
      donorId: _readString(map['donorId']),
      foodCategory: _readString(map['foodCategory']),
      storageMethod: _readString(map['storageMethod']),
      quantity: rawQuantity is num && rawQuantity.isFinite
          ? rawQuantity.toInt()
          : 0,
      allergens: _readString(map['allergens']),
      preparedAt: _readDate(map['preparedAt']),
      postedAt: _readDate(map['postedAt']),
      pickupDeadline: _readDate(map['pickupDeadline']),
      packagingState: _readString(map['packagingState']),
      eligibilityStatus: _readString(map['eligibilityStatus']),
      status: _readString(map['status']),
      pickupAddress: _readString(map['pickupAddress']),
      pickupCity: _readString(map['pickupCity']),
      pickupLocation: rawLocation is GeoPoint ? rawLocation : null,
    );
  }

  static String _readString(dynamic value) {
    return value is String ? value : '';
  }

  static DateTime _readDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    // A fixed fallback avoids making missing historical dates
    // appear to have happened at the current time.
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}