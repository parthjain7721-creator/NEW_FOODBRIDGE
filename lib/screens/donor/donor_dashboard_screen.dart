import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/fcm_token_service.dart';
import '../../widgets/dashboard_action_card.dart';
import '../../widgets/section_header.dart';
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
      await FcmTokenService.instance.signOutAndCleanup();
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
          padding: const EdgeInsets.all(20),
          children: [
            _buildWelcomeHeader(),
            const SizedBox(height: 24),
            DashboardActionCard(
              icon: Icons.volunteer_activism_outlined,
              title: 'Create a Donation Passport',
              description:
                  'Add food details, quantity, storage information, '
                  'packaging condition, allergens, and preparation time.',
              buttonLabel: 'Create donation',
              onPressed: _isSigningOut ? null : _openCreateDonation,
              primary: true,
            ),
            const SizedBox(height: 16),
            DashboardActionCard(
              icon: Icons.event_available_outlined,
              title: 'Confirm pickup arrangements',
              description:
                  'Review donations claimed by NGOs, check the planned '
                  'pickup time, and confirm that the donation is still '
                  'available for handover.',
              additionalInformation:
                  'The NGO must confirm receiving capacity and pickup '
                  'time before you can confirm the arrangement.',
              buttonLabel: 'View pickup confirmations',
              onPressed:
                  _isSigningOut ? null : _openPickupConfirmations,
            ),
            const SizedBox(height: 16),
            DashboardActionCard(
              icon: Icons.receipt_long_outlined,
              title: 'Track your donations',
              description:
                  'View your donation history and follow each donation '
                  'through NGO claim, pickup confirmation, volunteer '
                  'assignment, collection, delivery, and NGO review.',
              additionalInformation:
                  'Use the history filters to view active donations, '
                  'accepted deliveries, or other closed donations.',
              buttonLabel: 'My donation history',
              onPressed:
                  _isSigningOut ? null : _openDonationHistory,
            ),
            const SizedBox(height: 28),
            _buildWorkflowCard(),
            const SizedBox(height: 24),
            _buildDisclaimer(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF356B4D).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF356B4D),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.volunteer_activism_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Make a difference today',
                      style:
                          Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Share surplus food and follow its journey '
                      'to people who need it.',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade700,
                              ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'How donation and delivery work',
              subtitle:
                  'FoodBridge coordinates each donation through a clear '
                  'rescue workflow.',
              icon: Icons.route_outlined,
            ),
            const SizedBox(height: 8),
            _WorkflowStep(
              number: '1',
              title: 'Create a Donation Passport',
              description:
                  'Add the food details, quantity, storage information, '
                  'and pickup window.',
            ),
            _WorkflowStep(
              number: '2',
              title: 'NGO claims the donation',
              description:
                  'A nearby NGO reviews the donation and claims it for '
                  'receiving.',
            ),
            _WorkflowStep(
              number: '3',
              title: 'Confirm pickup arrangements',
              description:
                  'The NGO confirms capacity and pickup time, then you '
                  'confirm your availability.',
            ),
            _WorkflowStep(
              number: '4',
              title: 'Volunteer collects and delivers',
              description:
                  'A volunteer accepts the pickup task, collects the '
                  'donation, and delivers it to the NGO.',
            ),
            _WorkflowStep(
              number: '5',
              title: 'NGO completes the review',
              description:
                  'The receiving NGO accepts or rejects the delivered '
                  'donation.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Text(
      'FoodBridge calculates redistribution eligibility from '
      'declarations and rules. It does not certify food safety.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade700,
          ),
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  final String number;
  final String title;
  final String description;

  const _WorkflowStep({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF356B4D).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFF356B4D),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}