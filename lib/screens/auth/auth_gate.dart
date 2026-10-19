import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import '../home/authenticated_home_screen.dart';
import 'login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text('Unable to check authentication status.'),
            ),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        return FutureBuilder(
          future: FirestoreService().getUserProfile(user.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (profileSnapshot.hasError ||
                !profileSnapshot.hasData ||
                !profileSnapshot.data!.exists) {
              return const AuthenticatedHomeScreen();
            }

            final profile = profileSnapshot.data!.data();
            final role = profile?['role'] as String? ?? 'donor';

            return RoleHomeScreen(role: role);
          },
        );
      },
    );
  }
}

class RoleHomeScreen extends StatelessWidget {
  final String role;

  const RoleHomeScreen({
    super.key,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    switch (role) {
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

      case 'donor':
      default:
        return const RolePlaceholderScreen(
          title: 'Donor Dashboard',
          icon: Icons.volunteer_activism_outlined,
          description: 'Create and track your food donations.',
        );
    }
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

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
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
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              const Text(
                'This dashboard will be implemented in the next module.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}