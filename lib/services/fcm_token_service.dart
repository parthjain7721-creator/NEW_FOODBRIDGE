import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FcmTokenService {
  FcmTokenService._();

  static final FcmTokenService instance = FcmTokenService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _isInitialized = false;

  String? _lastSignedInUid;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _isInitialized = true;

    debugPrint('FcmTokenService: initialized.');

    _lastSignedInUid = _auth.currentUser?.uid;

    debugPrint(
      'FcmTokenService: initial signed-in UID = $_lastSignedInUid',
    );

    _auth.authStateChanges().listen(_handleAuthChange);

    FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) {
        debugPrint(
          'FcmTokenService: FCM token refreshed.',
        );

        _saveToken(token);
      },
    );
  }

  Future<void> _handleAuthChange(User? user) async {
    final String? previousUid = _lastSignedInUid;
    final String? currentUid = user?.uid;

    debugPrint(
      'FcmTokenService: auth changed. '
      'previousUid=$previousUid currentUid=$currentUid',
    );

    if (previousUid != null &&
        previousUid.isNotEmpty &&
        currentUid == null) {
      await _deleteTokensForUser(previousUid);
    }

    _lastSignedInUid = currentUid;
  }

  Future<void> requestPermissionAndRegisterToken() async {
    final String? uid = _auth.currentUser?.uid;

    debugPrint(
      'FcmTokenService: registration requested. uid=$uid',
    );

    if (uid == null || uid.isEmpty) {
      debugPrint(
        'FcmTokenService: no signed-in user; cannot register token.',
      );

      return;
    }

    if (kIsWeb) {
      debugPrint(
        'FcmTokenService: web is not enabled for FCM registration.',
      );

      return;
    }

    try {
      final NotificationSettings settings =
          await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint(
        'FcmTokenService: permission status = '
        '${settings.authorizationStatus}',
      );

      if (settings.authorizationStatus !=
              AuthorizationStatus.authorized &&
          settings.authorizationStatus !=
              AuthorizationStatus.provisional) {
        debugPrint(
          'FcmTokenService: notification permission was not granted.',
        );

        return;
      }

      final String? token = await _messaging.getToken();

      debugPrint(
        'FcmTokenService: getToken result = '
        '${token == null ? 'null' : 'received'}',
      );

      if (token == null || token.trim().isEmpty) {
        debugPrint(
          'FcmTokenService: FCM did not return a device token.',
        );

        return;
      }

      debugPrint(
        'FcmTokenService: FCM TOKEN: $token',
      );

      await _saveToken(token);
    } catch (exception, stackTrace) {
      debugPrint(
        'FcmTokenService: registration failed: $exception',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> signOutAndCleanup() async {
    final String? uid = _auth.currentUser?.uid;

    debugPrint(
      'FcmTokenService: signing out and cleaning up tokens. uid=$uid',
    );

    if (uid != null && uid.isNotEmpty) {
      await _deleteTokensForUser(uid);
    }

    await _auth.signOut();

    debugPrint(
      'FcmTokenService: user signed out.',
    );
  }

  Future<void> _saveToken(String token) async {
    final String? uid = _auth.currentUser?.uid;

    if (uid == null || uid.isEmpty) {
      debugPrint(
        'FcmTokenService: cannot save token because no user is signed in.',
      );

      return;
    }

    final String tokenId = _tokenId(token);

    debugPrint(
      'FcmTokenService: saving token. '
      'uid=$uid tokenId=$tokenId',
    );

    final DocumentReference<Map<String, dynamic>> tokenRef =
        _firestore.collection('fcmTokens').doc(tokenId);

    try {
      await _firestore.runTransaction<void>((transaction) async {
        final DocumentSnapshot<Map<String, dynamic>> snapshot =
            await transaction.get(tokenRef);

        final Map<String, dynamic>? existing = snapshot.data();

        if (existing != null && existing['userId'] != uid) {
          debugPrint(
            'FcmTokenService: token already belongs to another user.',
          );

          return;
        }

        final Map<String, dynamic> tokenData = {
          'userId': uid,
          'token': token,
          'platform': _platformName(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (!snapshot.exists) {
          tokenData['createdAt'] = FieldValue.serverTimestamp();
        }

        transaction.set(
          tokenRef,
          tokenData,
          SetOptions(merge: true),
        );
      });

      debugPrint(
        'FcmTokenService: token saved successfully to fcmTokens/$tokenId',
      );
    } on FirebaseException catch (exception, stackTrace) {
      debugPrint(
        'FcmTokenService: Firestore token save failed: '
        '${exception.code} — ${exception.message}',
      );

      debugPrintStack(stackTrace: stackTrace);
    } catch (exception, stackTrace) {
      debugPrint(
        'FcmTokenService: unexpected token save failure: $exception',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _deleteTokensForUser(String uid) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _firestore
              .collection('fcmTokens')
              .where('userId', isEqualTo: uid)
              .get();

      if (snapshot.docs.isEmpty) {
        debugPrint(
          'FcmTokenService: no FCM tokens found for uid=$uid',
        );

        return;
      }

      for (final QueryDocumentSnapshot<Map<String, dynamic>> document
          in snapshot.docs) {
        await document.reference.delete();

        debugPrint(
          'FcmTokenService: deleted FCM token ${document.id} '
          'for uid=$uid',
        );
      }

      debugPrint(
        'FcmTokenService: deleted all FCM tokens for uid=$uid',
      );
    } on FirebaseException catch (exception, stackTrace) {
      debugPrint(
        'FcmTokenService: deleting FCM tokens failed: '
        '${exception.code} — ${exception.message}',
      );

      debugPrintStack(stackTrace: stackTrace);
    } catch (exception, stackTrace) {
      debugPrint(
        'FcmTokenService: unexpected FCM token deletion failure: '
        '$exception',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String _tokenId(String token) {
    final List<int> tokenBytes = utf8.encode(token);

    return sha256.convert(tokenBytes).toString();
  }

  String _platformName() {
    if (kIsWeb) {
      return 'web';
    }

    if (Platform.isAndroid) {
      return 'android';
    }

    if (Platform.isIOS) {
      return 'ios';
    }

    if (Platform.isMacOS) {
      return 'macos';
    }

    return 'other';
  }
}