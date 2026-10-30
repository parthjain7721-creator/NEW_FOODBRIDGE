import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/login_screen.dart';
import '../donor/donor_dashboard_screen.dart';
import '../ngo/ngo_dashboard_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState ==
            ConnectionState.waiting) {
          return const _LoadingScreen(
            message: 'Checking your account...',
          );
        }

        if (authSnapshot.hasError) {
          return _DiagnosticScreen(
            title: 'Authentication error',
            details:
                'authStateChanges error:\n\n${authSnapshot.error}',
          );
        }

        final User? user = authSnapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        return UserProfileLoader(user: user);
      },
    );
  }
}

class UserProfileLoader extends StatefulWidget {
  final User user;

  const UserProfileLoader({
    super.key,
    required this.user,
  });

  @override
  State<UserProfileLoader> createState() =>
      _UserProfileLoaderState();
}

class _UserProfileLoaderState
    extends State<UserProfileLoader> {
  late Future<
      DocumentSnapshot<Map<String, dynamic>>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    debugPrint(
      'AuthGate loading profile for UID: '
      '${widget.user.uid}',
    );

    _profileFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .get();
  }

  void _retry() {
    setState(() {
      _loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
        DocumentSnapshot<Map<String, dynamic>>>(
      future: _profileFuture,
      builder: (context, profileSnapshot) {
        if (profileSnapshot.connectionState ==
            ConnectionState.waiting) {
          return const _LoadingScreen(
            message: 'Loading your FoodBridge profile...',
          );
        }

        if (profileSnapshot.hasError) {
          return _DiagnosticScreen(
            title: 'Firestore profile error',
            details:
                'User UID: ${widget.user.uid}\n\n'
                'Expected document:\n'
                'users/${widget.user.uid}\n\n'
                'Error:\n${profileSnapshot.error}',
            onRetry: _retry,
          );
        }

        final document = profileSnapshot.data;

        if (document == null || !document.exists) {
          return _DiagnosticScreen(
            title: 'Profile not found',
            details:
                'Firebase login succeeded.\n\n'
                'User UID: ${widget.user.uid}\n\n'
                'But this Firestore document does not exist:\n\n'
                'users/${widget.user.uid}\n\n'
                'Create this document manually or register again.',
            onRetry: _retry,
          );
        }

        final data = document.data();

        if (data == null) {
          return _DiagnosticScreen(
            title: 'Empty profile',
            details:
                'The Firestore document exists but contains no data.',
            onRetry: _retry,
          );
        }

        final role =
            (data['role'] as String? ?? '')
                .trim()
                .toLowerCase();

        debugPrint('Loaded role: $role');

        if (role.isEmpty) {
          return _DiagnosticScreen(
            title: 'Role missing',
            details:
                'The profile exists, but the role field is missing.\n\n'
                'Add: role = ngo',
            onRetry: _retry,
          );
        }

        switch (role) {
          case 'donor':
            return const DonorDashboardScreen();

          case 'ngo':
            return const NgoDashboardScreen();

          default:
            return _DiagnosticScreen(
              title: 'Invalid role',
              details:
                  'The profile role is "$role".\n\n'
                  'Allowed values are:\n'
                  'donor\n'
                  'ngo\n'
                  'volunteer',
              onRetry: _retry,
            );
        }
      },
    );
  }
}

class _DiagnosticScreen extends StatelessWidget {
  final String title;
  final String details;
  final VoidCallback? onRetry;

  const _DiagnosticScreen({
    required this.title,
    required this.details,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                details,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (onRetry != null)
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  final String message;

  const _LoadingScreen({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(message),
          ],
        ),
      ),
    );
  }
}