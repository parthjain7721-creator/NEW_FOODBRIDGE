import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'create_donation_screen.dart';
import 'donor_donation_history_screen.dart';
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
    } on FirebaseAuthException catch (exception, stackTrace) {
      debugPrint(
        'Donor logout failed: '
        '${exception.code} - ${exception.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      _showError(
        'Unable to sign out. Please try again. '
        '(${exception.code})',
      );
    } catch (exception, stackTrace) {
      debugPrint('Unexpected donor logout error: $exception');
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

  void _openDonationHistory() {
    if (_isSigningOut) {
      return;
    }

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const DonorDonationHistoryScreen(),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

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

  Widget _dashboardCard({
    required IconData icon,
    required String title,
    required String description,
    required String buttonLabel,
    required IconData buttonIcon,
    required VoidCallback onPressed,
    String? additionalInformation,
    bool primary = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 48,
              color: const Color(0xFF356B4D),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(description),
            if (additionalInformation != null) ...[
              const SizedBox(height: 12),
              Text(additionalInformation),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: primary
                  ? ElevatedButton.icon(
                      onPressed: _isSigningOut ? null : onPressed,
                      icon: Icon(buttonIcon),
                      label: Text(buttonLabel),
                    )
                  : OutlinedButton.icon(
                      onPressed: _isSigningOut ? null : onPressed,
                      icon: Icon(buttonIcon),
                      label: Text(buttonLabel),
                    ),
            ),
          ],
        ),
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
            tooltip: 'Donation history',
            onPressed: _isSigningOut ? null : _openDonationHistory,
            icon: const Icon(Icons.history),
          ),
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
              'Share surplus food, coordinate collection, '
              'and follow your donation through delivery '
              'and NGO review.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),

            _dashboardCard(
              icon: Icons.volunteer_activism_outlined,
              title: 'Create a Donation Passport',
              description:
                  'Add food details, quantity, storage information, '
                  'packaging condition, allergens, and preparation time.',
              buttonLabel: 'Create donation',
              buttonIcon: Icons.add_circle_outline,
              onPressed: _openCreateDonation,
              primary: true,
            ),

            const SizedBox(height: 20),

            _dashboardCard(
              icon: Icons.event_available_outlined,
              title: 'Confirm pickup arrangements',
              description:
                  'Review donations claimed by NGOs, check the '
                  'planned pickup time, and confirm that the '
                  'donation is still available for handover.',
              additionalInformation:
                  'The NGO must confirm receiving capacity and '
                  'pickup time before you can confirm the arrangement.',
              buttonLabel: 'View pickup confirmations',
              buttonIcon: Icons.check_circle_outline,
              onPressed: _openPickupConfirmations,
            ),

            const SizedBox(height: 20),

            _dashboardCard(
              icon: Icons.history,
              title: 'Track your donations',
              description:
                  'View your donation history and expand a donation '
                  'to see its recorded progress: NGO claim, pickup '
                  'confirmations, volunteer assignment, collection, '
                  'delivery, and the NGO’s final decision.',
              additionalInformation:
                  'Use the history filters to view active donations, '
                  'accepted deliveries, or other closed donations.',
              buttonLabel: 'My donation history',
              buttonIcon: Icons.receipt_long_outlined,
              onPressed: _openDonationHistory,
            ),

            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How donation and delivery work',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Create a Donation Passport.\n\n'
                      '2. An NGO claims the donation.\n\n'
                      '3. The NGO confirms capacity and pickup time.\n\n'
                      '4. You confirm the pickup arrangement.\n\n'
                      '5. A volunteer accepts the pickup task.\n\n'
                      '6. The volunteer matches the Donation Passport '
                      'QR and records the pickup inspection.\n\n'
                      '7. After collection, the volunteer records '
                      'delivery handover to the receiving NGO.\n\n'
                      '8. The receiving NGO accepts or rejects '
                      'the delivery.\n\n'
                      '9. View the saved progress and final decision '
                      'in My donation history.',
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