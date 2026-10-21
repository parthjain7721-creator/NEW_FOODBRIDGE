import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
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
          return _ErrorScreen(
            message:
                'Authentication error:\n${authSnapshot.error}',
          );
        }

        final User? user = authSnapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        return UserProfileLoader(
          key: ValueKey(user.uid),
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

class _UserProfileLoaderState
    extends State<UserProfileLoader> {
  late Future<
      DocumentSnapshot<Map<String, dynamic>>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void didUpdateWidget(
    covariant UserProfileLoader oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.user.uid != widget.user.uid) {
      _loadProfile();
    }
  }

  void _loadProfile() {
    _profileFuture = FirestoreService().getUserProfile(
      widget.user.uid,
    );
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
          return _ProfileErrorScreen(
            title: 'Unable to load profile',
            message:
                'Your login succeeded, but Firestore profile loading failed.\n\n'
                'User UID: ${widget.user.uid}\n\n'
                'Error: ${profileSnapshot.error}',
            onRetry: _retry,
          );
        }

        final DocumentSnapshot<Map<String, dynamic>>?
            document = profileSnapshot.data;

        if (document == null || !document.exists) {
          return _ProfileErrorScreen(
            title: 'Profile not found',
            message:
                'Your authentication account exists, but this profile does not exist:\n\n'
                'users/${widget.user.uid}',
            onRetry: _retry,
          );
        }

        final Map<String, dynamic>? data = document.data();

        if (data == null) {
          return _ProfileErrorScreen(
            title: 'Empty profile',
            message:
                'The Firestore profile exists but contains no data.',
            onRetry: _retry,
          );
        }

        final String role = (data['role'] as String? ?? '')
            .trim()
            .toLowerCase();

        debugPrint(
          'Authenticated user UID: ${widget.user.uid}',
        );
        debugPrint('Loaded Firestore role: $role');

        if (role.isEmpty) {
          return _ProfileErrorScreen(
            title: 'Role missing',
            message:
                'Your profile does not contain a role.\n\n'
                'Set the role to donor, ngo, or volunteer.',
            onRetry: _retry,
          );
        }

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
        return const NgoDashboardScreen();

      case 'volunteer':
        return const RolePlaceholderScreen(
          title: 'Volunteer Dashboard',
          icon: Icons.delivery_dining_outlined,
          description:
              'View pickup tasks and delivery assignments.',
        );

      default:
        return UnknownRoleScreen(role: role);
    }
  }
}

class UnknownRoleScreen extends StatelessWidget {
  final String role;

  const UnknownRoleScreen({
    super.key,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invalid account role'),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'The role "$role" is not supported.\n\n'
            'Allowed roles are:\n'
            'donor\n'
            'ngo\n'
            'volunteer',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
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
    if (_isCreating) {
      return;
    }

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
      debugPrint(
        'Profile creation error: '
        '${error.code} - ${error.message}',
      );

      if (!mounted) {
        return;
      }

      _showError(
        'Profile creation failed: ${error.code}',
      );
    } catch (error) {
      debugPrint('Unexpected profile creation error: $error');

      if (!mounted) {
        return;
      }

      _showError('Unable to create your profile.');
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
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
            tooltip: 'Logout',
            onPressed: _isCreating
                ? null
                : () async {
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
            tooltip: 'Logout',
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
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium,
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

class _ProfileErrorScreen extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _ProfileErrorScreen({
    required this.title,
    required this.message,
    required this.onRetry,
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 72,
                color: Colors.orange,
              ),
              const SizedBox(height: 24),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Log out'),
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
            Text(
              message,
              textAlign: TextAlign.center,
            ),
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