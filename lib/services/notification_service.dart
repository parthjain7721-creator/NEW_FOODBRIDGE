import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../screens/ngo/donation_details_screen.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _isInitialized = true;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
      ),
      onDidReceiveNotificationResponse: _handleLocalNotificationTap,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
      const AndroidNotificationChannel(
        'foodbridge_donations',
        'FoodBridge donations',
        description: 'Donation and pickup workflow notifications',
        importance: Importance.high,
      ),
    );

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
    final String? donationId =
        message.data['donationId'] as String?;

    final String title =
        message.notification?.title ?? 'FoodBridge update';

    final String body =
        message.notification?.body ?? 'You have a new update.';

    await _showLocalNotification(
      title: title,
      body: body,
      donationId: donationId,
    );

    _showInAppBanner(
      title: title,
      body: body,
      donationId: donationId,
    );
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String? donationId,
  }) async {
    final int notificationId =
        DateTime.now().millisecondsSinceEpoch % 2147483647;

    await _localNotifications.show(
      notificationId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'foodbridge_donations',
          'FoodBridge donations',
          channelDescription:
              'Donation and pickup workflow notifications',
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'FoodBridge notification',
        ),
      ),
      payload: donationId,
    );
  }

  void _showInAppBanner({
    required String title,
    required String body,
    required String? donationId,
  }) {
    final BuildContext? context = navigatorKey.currentContext;

    if (context == null) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$title\n$body',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: donationId == null || donationId.trim().isEmpty
              ? null
              : SnackBarAction(
                  label: 'Open',
                  onPressed: () => _openDonationDetails(
                    donationId.trim(),
                  ),
                ),
        ),
      );
  }

  void _handleLocalNotificationTap(
    NotificationResponse response,
  ) {
    final String? donationId = response.payload;

    if (donationId == null || donationId.trim().isEmpty) {
      return;
    }

    _openDonationDetails(donationId.trim());
  }

  Future<void> _handleNotificationTap(
    RemoteMessage message,
  ) async {
    final String? donationId =
        message.data['donationId'] as String?;

    if (donationId == null || donationId.trim().isEmpty) {
      return;
    }

    _openDonationDetails(donationId.trim());
  }

  void _openDonationDetails(String donationId) {
    final NavigatorState? navigator = navigatorKey.currentState;

    if (navigator == null) {
      return;
    }

    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => DonationDetailsScreen(
          donationId: donationId,
        ),
      ),
      (route) => false,
    );
  }
}