import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/donation_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
      'role': role,
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
  Future<String> createDonation(DonationModel donation) async {
  final document = _firestore.collection('donations').doc();

  await document.set({
    ...donation.toMap(),
    'donationId': document.id,
  });

  return document.id;
}
} 