import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/donation_model.dart';

class DonationPassportScreen extends StatelessWidget {
  final DonationModel donation;
  final String explanation;

  const DonationPassportScreen({
    super.key,
    required this.donation,
    required this.explanation,
  });

  String _formatDate(DateTime value) {
    final local = value.toLocal();

    String twoDigits(int number) {
      return number.toString().padLeft(2, '0');
    }

    return '${local.day}/${twoDigits(local.month)}/${local.year} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'eligible':
        return 'Eligible for pickup now';
      case 'urgent':
        return 'Urgent pickup required';
      case 'manual_review':
        return 'Needs manual NGO review';
      case 'not_eligible':
        return 'Not eligible for redistribution';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'eligible':
        return const Color(0xFF356B4D);
      case 'urgent':
        return Colors.orange.shade800;
      case 'manual_review':
        return Colors.blue.shade800;
      case 'not_eligible':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  String _storageLabel(String value) {
    switch (value) {
      case 'room_temperature':
        return 'Room temperature';
      case 'refrigerated':
        return 'Refrigerated';
      case 'frozen':
        return 'Frozen';
      case 'unknown':
        return 'Unknown';
      default:
        return value;
    }
  }

  String _packagingLabel(String value) {
    switch (value) {
      case 'sealed':
        return 'Sealed';
      case 'intact':
        return 'Intact';
      case 'damaged':
        return 'Damaged';
      case 'leaking':
        return 'Leaking';
      default:
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(donation.eligibilityStatus);

    final qrData = '''
FoodBridge Donation Passport
Donation ID: ${donation.id}
Food category: ${donation.foodCategory}
Quantity: ${donation.quantity}
Prepared at: ${_formatDate(donation.preparedAt)}
Pickup deadline: ${_formatDate(donation.pickupDeadline)}
Status: ${_statusLabel(donation.eligibilityStatus)}
''';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Donation Passport'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      size: 48,
                      color: statusColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _statusLabel(donation.eligibilityStatus),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: statusColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      explanation,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Scan to view donation details',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _InfoCard(
                title: 'Donation ID',
                value: donation.id,
                icon: Icons.tag_outlined,
              ),
              _InfoCard(
                title: 'Food category',
                value: donation.foodCategory,
                icon: Icons.restaurant_outlined,
              ),
              _InfoCard(
                title: 'Quantity',
                value: '${donation.quantity} portions or packets',
                icon: Icons.inventory_2_outlined,
              ),
              _InfoCard(
                title: 'Prepared at',
                value: _formatDate(donation.preparedAt),
                icon: Icons.schedule_outlined,
              ),
              _InfoCard(
                title: 'Pickup deadline',
                value: _formatDate(donation.pickupDeadline),
                icon: Icons.timer_outlined,
              ),
              _InfoCard(
                title: 'Storage method',
                value: _storageLabel(donation.storageMethod),
                icon: Icons.kitchen_outlined,
              ),
              _InfoCard(
                title: 'Packaging condition',
                value: _packagingLabel(donation.packagingState),
                icon: Icons.inventory_outlined,
              ),
              _InfoCard(
                title: 'Allergens',
                value: donation.allergens.isEmpty
                    ? 'None declared'
                    : donation.allergens,
                icon: Icons.warning_amber_outlined,
              ),
              const SizedBox(height: 16),
              const Text(
                'This Donation Passport records donor declarations and workflow verification. It does not certify food safety.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Back to dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _InfoCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          icon,
          color: const Color(0xFF356B4D),
        ),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }
}