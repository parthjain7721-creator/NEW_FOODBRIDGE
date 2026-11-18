import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../screens/notifications/notification_center_screen.dart';
import '../services/local_notification_store.dart';

class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({super.key});

  @override
  State<NotificationBellButton> createState() =>
      _NotificationBellButtonState();
}

class _NotificationBellButtonState
    extends State<NotificationBellButton> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();

    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _unreadCount = 0;
      });

      return;
    }

    try {
      final int unreadCount =
          await LocalNotificationStore.instance.getUnreadCount(uid);

      if (!mounted) {
        return;
      }

      setState(() {
        _unreadCount = unreadCount;
      });
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
    return IconButton(
      tooltip: 'Notifications',
      onPressed: _openNotificationCenter,
      icon: Badge(
        isLabelVisible: _unreadCount > 0,
        label: Text(
          _unreadCount > 99 ? '99+' : _unreadCount.toString(),
        ),
        child: const Icon(Icons.notifications),
      ),
    );
  }
}