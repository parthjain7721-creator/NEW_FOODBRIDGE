import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/splash/splash_screen.dart';

class FoodBridgeApp extends StatelessWidget {
  const FoodBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FoodBridge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AppStartupScreen(),
    );
  }
}

class AppStartupScreen extends StatefulWidget {
  const AppStartupScreen({super.key});

  @override
  State<AppStartupScreen> createState() => _AppStartupScreenState();
}

class _AppStartupScreenState extends State<AppStartupScreen> {
  bool _showAuthGate = false;

  @override
  void initState() {
    super.initState();

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      setState(() {
        _showAuthGate = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showAuthGate) {
      return const SplashScreen();
    }

    return const AuthGate();
  }
}