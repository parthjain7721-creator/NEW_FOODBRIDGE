import 'package:flutter/foundation.dart';

class NotificationBadgeService {
  NotificationBadgeService._();

  static final NotificationBadgeService instance =
      NotificationBadgeService._();

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  void setUnreadCount(int count) {
    unreadCount.value = count < 0 ? 0 : count;
  }

  void incrementUnreadCount() {
    unreadCount.value = unreadCount.value + 1;
  }

  void reset() {
    unreadCount.value = 0;
  }
}