import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/notifications/notification_center_screen.dart';
import '../services/local_notification_store.dart';
import '../services/notification_badge_service.dart';

class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({super.key});

  @override
  State<NotificationBellButton> createState() =>
      _NotificationBellButtonState();
}

class _NotificationBellButtonState
    extends State<NotificationBellButton> {
  @override
  void initState() {
    super.initState();

    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid.isEmpty) {
      NotificationBadgeService.instance.reset();
      return;
    }

    try {
      final int unreadCount =
          await LocalNotificationStore.instance.getUnreadCount(uid);

      NotificationBadgeService.instance.setUnreadCount(unreadCount);
    } catch (error) {
      debugPrint(
        'NotificationBellButton: unable to load unread count: $error',
      );
    }
  }

  Future<void> _openNotificationCenter() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid.isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          arguments: uid,
        ),
        builder: (_) => const NotificationCenterScreen(),
      ),
    );

    await _loadUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationBadgeService.instance.unreadCount,
      builder: (BuildContext context, int unreadCount, _) {
        return IconButton(
          tooltip: 'Notifications',
          onPressed: _openNotificationCenter,
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(
              unreadCount > 99 ? '99+' : unreadCount.toString(),
            ),
            child: const Icon(Icons.notifications),
          ),
        );
      },
    );
  }
}