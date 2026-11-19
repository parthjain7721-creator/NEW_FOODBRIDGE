import 'package:flutter/material.dart';

import '../../models/app_notification.dart';
import '../../services/local_notification_store.dart';
import '../ngo/donation_details_screen.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends State<NotificationCenterScreen> {
  List<AppNotification> _notifications = <AppNotification>[];

  bool _isLoading = true;

  String? _errorMessage;

  String? _uid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final String? uid = _getCurrentUid();

    if (uid == null || uid.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'You must be signed in to view notifications.';
      });

      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final List<AppNotification> notifications =
          await LocalNotificationStore.instance.getNotifications(uid);

      if (!mounted) {
        return;
      }

      setState(() {
        _uid = uid;
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint(
        'NotificationCenterScreen: unable to load notifications: '
        '$error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'Unable to load notifications. Please try again.';
      });
    }
  }

  String? _getCurrentUid() {
    final Object? arguments =
        ModalRoute.of(context)?.settings.arguments;

    if (arguments is String && arguments.trim().isNotEmpty) {
      return arguments.trim();
    }

    return null;
  }

  Future<void> _markAllRead() async {
    final String? uid = _uid;

    if (uid == null || uid.isEmpty) {
      return;
    }

    await LocalNotificationStore.instance.markAllNotificationsRead(
      uid: uid,
    );

    await _loadNotifications();
  }

  Future<void> _clearAll() async {
    final String? uid = _uid;

    if (uid == null || uid.isEmpty) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Clear notifications?'),
          content: const Text(
            'This will remove all notifications from this device. '
            'This action cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Clear all'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await LocalNotificationStore.instance.clearAllNotifications(
      uid: uid,
    );

    await _loadNotifications();
  }

  Future<void> _openNotification(
    AppNotification notification,
  ) async {
    final String? uid = _uid;

    if (uid != null && uid.isNotEmpty) {
      await LocalNotificationStore.instance.markNotificationRead(
        uid: uid,
        notificationId: notification.id,
      );
    }

    if (!mounted) {
      return;
    }

    final String donationId = notification.donationId.trim();

    if (donationId.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'This notification is not linked to a donation.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );

      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DonationDetailsScreen(
          donationId: donationId,
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final DateTime localDateTime = dateTime.toLocal();

    final String hour =
        localDateTime.hour.toString().padLeft(2, '0');

    final String minute =
        localDateTime.minute.toString().padLeft(2, '0');

    return '${localDateTime.day}/'
        '${localDateTime.month}/'
        '${localDateTime.year} '
        '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final int unreadCount = _notifications
        .where((AppNotification notification) => !notification.isRead)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          if (_notifications.isNotEmpty) ...[
            IconButton(
              tooltip: 'Mark all read',
              onPressed: unreadCount == 0 ? null : _markAllRead,
              icon: const Icon(Icons.done_all),
            ),
            IconButton(
              tooltip: 'Clear all',
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep),
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.error_outline,
                size: 56,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadNotifications,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_notifications.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.notifications_none,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                'No notifications yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Workflow updates will appear here when donations '
                'change.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _notifications.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          final AppNotification notification = _notifications[index];

          return _NotificationCard(
            notification: notification,
            timeText: _formatTime(notification.createdAt),
            onTap: () => _openNotification(notification),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final String timeText;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.timeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isUnread = !notification.isRead;

    return Card(
      elevation: isUnread ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                isUnread
                    ? Icons.notifications_active
                    : Icons.notifications_none,
                color: isUnread ? Colors.blue : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: isUnread
                            ? FontWeight.bold
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timeText,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}