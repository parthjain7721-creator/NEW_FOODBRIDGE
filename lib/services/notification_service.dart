import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';


import '../screens/ngo/donation_details_screen.dart';


class NotificationService {
  NotificationService._();


  static final NotificationService instance =
      NotificationService._();


  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();


  bool _isInitialized = false;


  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }


    _isInitialized = true;


    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);


    FirebaseMessaging.onMessageOpenedApp.listen(
      _handleNotificationTap,
    );


    final RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();


    if (initialMessage != null) {
      await _handleNotificationTap(initialMessage);
    }
  }


  Future<void> _handleForegroundMessage(
    RemoteMessage message,
  ) async {
    debugPrint(
      'Foreground FCM message received: ${message.messageId}',
    );


    debugPrint(
      'Notification: ${message.notification?.title} — '
      '${message.notification?.body}',
    );
  }


  Future<void> _handleNotificationTap(
    RemoteMessage message,
  ) async {
    final String? donationId =
        message.data['donationId'] as String?;


    if (donationId == null || donationId.trim().isEmpty) {
      return;
    }


    final NavigatorState? navigator =
        navigatorKey.currentState;


    if (navigator == null) {
      return;
    }


    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => DonationDetailsScreen(
          donationId: donationId.trim(),
        ),
      ),
      (route) => false,
    );
  }
}