import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'create_donation_screen.dart';
import 'donor_pickup_confirmations_screen.dart';

class DonorDashboardScreen extends StatefulWidget {
  const DonorDashboardScreen({super.key});

  @override
  State<DonorDashboardScreen> createState() =>
      _DonorDashboardScreenState();
}

class _DonorDashboardScreenState
    extends State<DonorDashboardScreen> {
  bool _isSigningOut = false;

  Future<void> _logout() async {
    if (_isSigningOut) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      await FirebaseAuth.instance.signOut();

      // AuthGate handles the transition back to Login.
      // Do not push a separate LoginScreen here.
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'Donor logout failed: ${error.code} - ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showError(
        'Unable to sign out. Please try again. (${error.code})',
      );
    } catch (error, stackTrace) {
      debugPrint('Unexpected donor logout error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showError('Unable to sign out. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  void _openCreateDonation() {
    if (_isSigningOut) {
      return;
    }

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const CreateDonationScreen(),
      ),
    );
  }

  void _openPickupConfirmations() {
    if (_isSigningOut) {
      return;
    }

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const DonorPickupConfirmationsScreen(),
      ),
    );
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
        title: const Text('Donor Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Pickup confirmations',
            onPressed:
                _isSigningOut ? null : _openPickupConfirmations,
            icon: const Icon(Icons.event_available_outlined),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _isSigningOut ? null : _logout,
            icon: _isSigningOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Make a difference today',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Share surplus food and coordinate its collection '
              'before the pickup window closes.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),

            // Donation creation.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.volunteer_activism_outlined,
                      size: 48,
                      color: Color(0xFF356B4D),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Create a Donation Passport',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add food details, quantity, storage information, '
                      'packaging condition, allergens, and preparation time.',
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _isSigningOut ? null : _openCreateDonation,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Create donation'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Donor confirmation for claimed donations.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.event_available_outlined,
                      size: 48,
                      color: Color(0xFF356B4D),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Confirm pickup arrangements',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Review donations claimed by NGOs, check the '
                      'planned pickup time, and confirm that the '
                      'donation is still available for handover.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'The NGO must confirm receiving capacity and '
                      'pickup time before you can confirm the arrangement.',
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isSigningOut
                            ? null
                            : _openPickupConfirmations,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('View pickup confirmations'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Workflow explanation.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How collection works',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Create a Donation Passport.\n\n'
                      '2. An NGO claims the donation.\n\n'
                      '3. The NGO confirms capacity and pickup time.\n\n'
                      '4. You confirm the pickup arrangement.\n\n'
                      '5. Volunteer assignment and pickup verification '
                      'will follow in the next module.',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'FoodBridge calculates redistribution eligibility from '
              'declarations and rules. It does not certify food safety.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}