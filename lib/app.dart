import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/splash/splash_screen.dart';

class FoodBridgeApp extends StatelessWidget {
  const FoodBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FoodBridge',
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
