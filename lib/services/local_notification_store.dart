import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification.dart';

class LocalNotificationStore {
  LocalNotificationStore._();

  static final LocalNotificationStore instance =
      LocalNotificationStore._();

  static const int _maximumNotifications = 50;

  String _storageKey(String uid) {
    return 'foodbridge_notifications_$uid';
  }

  Future<List<AppNotification>> getNotifications(
    String uid,
  ) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();

    final String? rawNotifications =
        preferences.getString(_storageKey(uid));

    if (rawNotifications == null || rawNotifications.isEmpty) {
      return <AppNotification>[];
    }

    try {
      final Object? decoded = jsonDecode(rawNotifications);

      if (decoded is! List) {
        return <AppNotification>[];
      }

      final List<AppNotification> notifications =
          decoded
              .whereType<Map<String, dynamic>>()
              .map(AppNotification.fromMap)
              .toList();

      notifications.sort(
        (a, b) => b.createdAt.compareTo(a.createdAt),
      );

      return notifications;
    } catch (error) {
      return <AppNotification>[];
    }
  }

  Future<void> addNotification({
    required String uid,
    required AppNotification notification,
  }) async {
    final List<AppNotification> notifications =
        await getNotifications(uid);

    final bool alreadyExists = notifications.any(
      (AppNotification existing) => existing.id == notification.id,
    );

    if (alreadyExists) {
      return;
    }

    notifications.insert(0, notification);

    final List<AppNotification> limitedNotifications =
        notifications.take(_maximumNotifications).toList();

    await _saveNotifications(
      uid: uid,
      notifications: limitedNotifications,
    );
  }

  Future<void> markNotificationRead({
    required String uid,
    required String notificationId,
  }) async {
    final List<AppNotification> notifications =
        await getNotifications(uid);

    final List<AppNotification> updatedNotifications =
        notifications.map((AppNotification notification) {
      if (notification.id == notificationId) {
        return notification.copyWith(isRead: true);
      }

      return notification;
    }).toList();

    await _saveNotifications(
      uid: uid,
      notifications: updatedNotifications,
    );
  }

  Future<void> markAllNotificationsRead({
    required String uid,
  }) async {
    final List<AppNotification> notifications =
        await getNotifications(uid);

    final List<AppNotification> updatedNotifications =
        notifications
            .map(
              (AppNotification notification) =>
                  notification.copyWith(isRead: true),
            )
            .toList();

    await _saveNotifications(
      uid: uid,
      notifications: updatedNotifications,
    );
  }

  Future<void> clearAllNotifications({
    required String uid,
  }) async {
    await _saveNotifications(
      uid: uid,
      notifications: <AppNotification>[],
    );
  }

  Future<int> getUnreadCount(String uid) async {
    final List<AppNotification> notifications =
        await getNotifications(uid);

    return notifications
        .where((AppNotification notification) => !notification.isRead)
        .length;
  }

  Future<void> _saveNotifications({
    required String uid,
    required List<AppNotification> notifications,
  }) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();

    final String encodedNotifications = jsonEncode(
      notifications.map(
        (AppNotification notification) => notification.toMap(),
      ).toList(),
    );

    await preferences.setString(
      _storageKey(uid),
      encodedNotifications,
    );
  }
}