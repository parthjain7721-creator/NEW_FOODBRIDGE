import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import '../auth/login_screen.dart';
import '../donor/donor_dashboard_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(
            message: 'Checking your account...',
          );
        }

        if (authSnapshot.hasError) {
          return const _ErrorScreen(
            message: 'Authentication could not be checked.',
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

class UserProfileLoader extends StatelessWidget {
  final User user;

  const UserProfileLoader({
    super.key,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
        DocumentSnapshot<Map<String, dynamic>>>(
      future: FirestoreService().getUserProfile(user.uid),
      builder: (context, profileSnapshot) {
        if (profileSnapshot.connectionState ==
            ConnectionState.waiting) {
          return const _LoadingScreen(
            message: 'Loading your FoodBridge profile...',
          );
        }

        if (profileSnapshot.hasError) {
          return ProfileRecoveryScreen(
            user: user,
            errorMessage:
                'Could not load your Firestore profile.',
          );
        }

        final document = profileSnapshot.data;

        if (document == null || !document.exists) {
          return ProfileRecoveryScreen(
            user: user,
            errorMessage:
                'Your authentication account exists, but your FoodBridge profile is missing.',
          );
        }

        final Map<String, dynamic>? data = document.data();
        final String role = data?['role'] as String? ?? 'donor';

        return RoleDashboard(role: role);
      },
    );
  }
}

class RoleDashboard extends StatelessWidget {
  final String role;

  const RoleDashboard({
    super.key,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    switch (role) {
      case 'donor':
        return const DonorDashboardScreen();

      case 'ngo':
        return const RolePlaceholderScreen(
          title: 'NGO Dashboard',
          icon: Icons.home_work_outlined,
          description: 'View and claim available food donations.',
        );

      case 'volunteer':
        return const RolePlaceholderScreen(
          title: 'Volunteer Dashboard',
          icon: Icons.delivery_dining_outlined,
          description: 'View pickup tasks and delivery assignments.',
        );

      default:
        return const RolePlaceholderScreen(
          title: 'FoodBridge Dashboard',
          icon: Icons.dashboard_outlined,
          description: 'Your account is ready.',
        );
    }
  }
}

class ProfileRecoveryScreen extends StatefulWidget {
  final User user;
  final String errorMessage;

  const ProfileRecoveryScreen({
    super.key,
    required this.user,
    required this.errorMessage,
  });

  @override
  State<ProfileRecoveryScreen> createState() =>
      _ProfileRecoveryScreenState();
}

class _ProfileRecoveryScreenState
    extends State<ProfileRecoveryScreen> {
  bool _isCreating = false;

  Future<void> _createMissingProfile() async {
    setState(() {
      _isCreating = true;
    });

    try {
      await FirestoreService().createUserProfile(
        uid: widget.user.uid,
        email: widget.user.email ?? '',
        role: 'donor',
        name: widget.user.displayName ?? 'FoodBridge User',
        phone: '',
        organizationName: '',
      );

      if (!mounted) {
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const DonorDashboardScreen(),
        ),
        (route) => false,
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      _showError(
        'Profile creation failed: ${error.code}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showError(
        'Unable to create your profile.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete profile'),
        actions: [
          IconButton(
            onPressed: _isCreating ? null : _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.person_off_outlined,
                size: 72,
                color: Colors.orange,
              ),
              const SizedBox(height: 24),
              Text(
                widget.errorMessage,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCreating
                      ? null
                      : _createMissingProfile,
                  child: _isCreating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Create donor profile'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RolePlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String description;

  const RolePlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 80,
                color: const Color(0xFF356B4D),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
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

class _ErrorScreen extends StatelessWidget {
  final String message;

  const _ErrorScreen({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}