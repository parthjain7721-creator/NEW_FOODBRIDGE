import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../donor/donor_dashboard_screen.dart';
import '../ngo/ngo_dashboard_screen.dart';
import '../volunteer/volunteer_dashboard_screen.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<User?> _authStream;

  @override
  void initState() {
    super.initState();

    _authStream = FirebaseAuth.instance.authStateChanges();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _DiagnosticScreen(
            title: 'Authentication error',
            details:
                'Unable to check your login session.\n\n'
                '${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(
            message: 'Checking your account...',
          );
        }

        final User? user = snapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        return UserProfileLoader(
          key: ValueKey<String>(user.uid),
          user: user,
        );
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

class _UserProfileLoaderState extends State<UserProfileLoader> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream;

  @override
  void initState() {
    super.initState();

    _connectProfile();
  }

  @override
  void didUpdateWidget(covariant UserProfileLoader oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.user.uid != widget.user.uid) {
      _connectProfile();
    }
  }

  void _connectProfile() {
    debugPrint(
      'AuthGate: listening to users/${widget.user.uid}',
    );

    _profileStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .snapshots();
  }

  void _retry() {
    setState(() {
      _connectProfile();
    });
  }

  String _profileErrorMessage(Object? error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Your login succeeded, but Firestore denied access '
              'to your profile.\n\n'
              'Check the deployed users/{uid} security rules.\n\n'
              'Error code: ${error.code}';

        case 'unavailable':
          return 'Your login succeeded, but Firestore is currently '
              'unavailable. Check your Internet connection.\n\n'
              'Error code: ${error.code}';

        default:
          return 'Your login succeeded, but your profile could not '
              'be loaded.\n\n'
              'Error code: ${error.code}\n'
              '${error.message ?? ''}';
      }
    }

    return 'Your profile could not be loaded.\n\n$error';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profileStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _DiagnosticScreen(
            title: 'Unable to load profile',
            details:
                '${_profileErrorMessage(snapshot.error)}\n\n'
                'Profile path:\nusers/${widget.user.uid}',
            onRetry: _retry,
          );
        }

        if (!snapshot.hasData) {
          return const _LoadingScreen(
            message: 'Loading your FoodBridge profile...',
          );
        }

        final DocumentSnapshot<Map<String, dynamic>> document =
            snapshot.data!;

        if (!document.exists) {
          return _DiagnosticScreen(
            title: 'Profile not available yet',
            details:
                'Your login account exists, but its FoodBridge '
                'profile is not available.\n\n'
                'If registration is still saving the profile, '
                'this screen will update automatically.\n\n'
                'If registration already failed, complete profile '
                'recovery for this existing account instead of '
                'creating the same account again.\n\n'
                'Profile path:\nusers/${widget.user.uid}',
            onRetry: _retry,
          );
        }

        final Map<String, dynamic>? data = document.data();

        if (data == null) {
          return _DiagnosticScreen(
            title: 'Empty profile',
            details:
                'Your profile document exists but contains no data.\n\n'
                'Profile path:\nusers/${widget.user.uid}',
            onRetry: _retry,
          );
        }

        final Object? rawRole = data['role'];

        final String role = rawRole is String
            ? rawRole.trim().toLowerCase()
            : '';

        if (role.isEmpty) {
          return _DiagnosticScreen(
            title: 'Account role missing',
            details:
                'Your profile needs a valid string role:\n\n'
                'donor, ngo, or volunteer\n\n'
                'Profile path:\nusers/${widget.user.uid}',
            onRetry: _retry,
          );
        }

        if (data['isActive'] == false) {
          return const _DiagnosticScreen(
            title: 'Account inactive',
            details:
                'Your FoodBridge profile is marked inactive. '
                'Contact the project administrator.',
          );
        }

        switch (role) {
          case 'donor':
            return const DonorDashboardScreen();

          case 'ngo':
            return const NgoDashboardScreen();

          case 'volunteer':
            return const VolunteerDashboardScreen();

          default:
            return _DiagnosticScreen(
              title: 'Unsupported account role',
              details:
                  'The profile contains an unsupported role: "$role".\n\n'
                  'Supported roles:\n'
                  'donor\n'
                  'ngo\n'
                  'volunteer\n\n'
                  'Profile path:\nusers/${widget.user.uid}',
              onRetry: _retry,
            );
        }
      },
    );
  }
}

Future<void> _signOut(BuildContext context) async {
  try {
    await FirebaseAuth.instance.signOut();
  } catch (error) {
    debugPrint('Sign-out failed: $error');

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Unable to sign out. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
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
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline,
                size: 64,
                color: Colors.orange,
              ),
              const SizedBox(height: 20),
              SelectableText(
                details,
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout),
                label: const Text('Return to login'),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}