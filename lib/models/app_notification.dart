import 'dart:convert';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String donationId;
  final DateTime createdAt;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.donationId,
    required this.createdAt,
    required this.isRead,
  });

  AppNotification copyWith({
    String? id,
    String? title,
    String? body,
    String? donationId,
    DateTime? createdAt,
    bool? isRead,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      donationId: donationId ?? this.donationId,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'body': body,
      'donationId': donationId,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
    };
  }

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      donationId: map['donationId'] as String? ?? '',
      createdAt: DateTime.tryParse(
            map['createdAt'] as String? ?? '',
          ) ??
          DateTime.now(),
      isRead: map['isRead'] as bool? ?? false,
    );
  }

  String toJson() {
    return jsonEncode(toMap());
  }

  factory AppNotification.fromJson(String json) {
    final Map<String, dynamic> map =
        jsonDecode(json) as Map<String, dynamic>;

    return AppNotification.fromMap(map);
  }
}