import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';


import 'app.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';


@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );


  debugPrint(
    'Background FCM message received: ${message.messageId}',
  );
}


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );


  FirebaseMessaging.onBackgroundMessage(
    _firebaseMessagingBackgroundHandler,
  );


  await NotificationService.instance.initialize();


  runApp(const FoodBridgeApp());
}