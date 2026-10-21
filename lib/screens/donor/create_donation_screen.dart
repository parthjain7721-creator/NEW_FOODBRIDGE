
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/donation_model.dart';
import '../../services/eligibility_service.dart';
import '../../services/firestore_service.dart';
import 'donation_passport_screen.dart';

class CreateDonationScreen extends StatefulWidget {
  const CreateDonationScreen({super.key});

  @override
  State<CreateDonationScreen> createState() =>
      _CreateDonationScreenState();
}

class _CreateDonationScreenState
    extends State<CreateDonationScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();

  final TextEditingController _quantityController =
      TextEditingController();
  final TextEditingController _allergensController =
      TextEditingController();

  final List<String> _foodCategories = [
    'Cooked meal',
    'Bakery',
    'Fruits and vegetables',
    'Packaged food',
  ];

  final List<String> _storageMethods = [
    'room_temperature',
    'refrigerated',
    'frozen',
    'unknown',
  ];

  final List<String> _packagingStates = [
    'sealed',
    'intact',
    'damaged',
    'leaking',
  ];

  String _foodCategory = 'Cooked meal';
  String _storageMethod = 'room_temperature';
  String _packagingState = 'sealed';

  DateTime _preparedAt = DateTime.now().subtract(
    const Duration(minutes: 30),
  );

  bool _isLoading = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _allergensController.dispose();
    super.dispose();
  }

  Future<void> _selectPreparationTime() async {
    final DateTime now = DateTime.now();

    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: _preparedAt,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
    );

    if (selectedDate == null || !mounted) {
      return;
    }

    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_preparedAt),
    );

    if (selectedTime == null || !mounted) {
      return;
    }

    final DateTime selectedDateTime = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    if (selectedDateTime.isAfter(now)) {
      _showMessage(
        'Preparation time cannot be in the future.',
        Colors.orange.shade800,
      );
      return;
    }

    setState(() {
      _preparedAt = selectedDateTime;
    });
  }

  Future<void> _submitDonation() async {
    if (_isLoading) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage(
        'Your login session has expired. Please log in again.',
        Colors.red.shade700,
      );
      return;
    }

    final int? quantity = int.tryParse(
      _quantityController.text.trim(),
    );

    if (quantity == null || quantity <= 0) {
      _showMessage(
        'Enter a valid quantity.',
        Colors.orange.shade800,
      );
      return;
    }

    final DateTime now = DateTime.now();

    if (_preparedAt.isAfter(now)) {
      _showMessage(
        'Preparation time cannot be in the future.',
        Colors.orange.shade800,
      );
      return;
    }

    final EligibilityResult eligibility =
        EligibilityService.calculate(
      preparedAt: _preparedAt,
      now: now,
      foodCategory: _foodCategory,
      storageMethod: _storageMethod,
      packagingState: _packagingState,
    );

    setState(() {
      _isLoading = true;
    });

    try {
      final DonationModel draftDonation = DonationModel(
        id: '',
        donorId: user.uid,
        foodCategory: _foodCategory,
        storageMethod: _storageMethod,
        quantity: quantity,
        allergens: _allergensController.text.trim(),
        preparedAt: _preparedAt,
        postedAt: now,
        pickupDeadline: now.add(
          Duration(minutes: eligibility.remainingMinutes),
        ),
        packagingState: _packagingState,
        eligibilityStatus: eligibility.status,
        status: 'available',
      );

      debugPrint(
        'Creating donation for donor UID: ${user.uid}',
      );

      final String donationId =
          await _firestoreService.createDonation(
        draftDonation,
      );

      final DonationModel savedDonation = DonationModel(
        id: donationId,
        donorId: draftDonation.donorId,
        foodCategory: draftDonation.foodCategory,
        storageMethod: draftDonation.storageMethod,
        quantity: draftDonation.quantity,
        allergens: draftDonation.allergens,
        preparedAt: draftDonation.preparedAt,
        postedAt: draftDonation.postedAt,
        pickupDeadline: draftDonation.pickupDeadline,
        packagingState: draftDonation.packagingState,
        eligibilityStatus: draftDonation.eligibilityStatus,
        status: draftDonation.status,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DonationPassportScreen(
            donation: savedDonation,
            explanation: eligibility.explanation,
          ),
        ),
      );
    } on FirebaseException catch (error) {
      debugPrint(
        'Donation Firestore error: '
        '${error.code} - ${error.message}',
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Firestore error: ${error.code}',
        Colors.red.shade700,
      );
    } catch (error) {
      debugPrint(
        'Unexpected donation creation error: $error',
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to save donation: $error',
        Colors.red.shade700,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
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

  String _formatDateTime(DateTime value) {
    final DateTime local = value.toLocal();

    String twoDigits(int number) {
      return number.toString().padLeft(2, '0');
    }

    return '${local.day}/${twoDigits(local.month)}/${local.year} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create donation'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Donation details',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'FoodBridge calculates a transparent rescue status '
                  'from your declarations.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                DropdownButtonFormField<String>(
                  initialValue: _foodCategory,
                  decoration: const InputDecoration(
                    labelText: 'Food category',
                    prefixIcon: Icon(Icons.restaurant_outlined),
                  ),
                  items: _foodCategories.map((category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: _isLoading
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _foodCategory = value;
                          });
                        },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    hintText: 'Number of portions or packets',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (value) {
                    final int? quantity = int.tryParse(
                      value?.trim() ?? '',
                    );

                    if (quantity == null || quantity <= 0) {
                      return 'Enter a valid quantity';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _storageMethod,
                  decoration: const InputDecoration(
                    labelText: 'Storage method',
                    prefixIcon: Icon(Icons.kitchen_outlined),
                  ),
                  items: _storageMethods.map((method) {
                    return DropdownMenuItem<String>(
                      value: method,
                      child: Text(_storageLabel(method)),
                    );
                  }).toList(),
                  onChanged: _isLoading
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _storageMethod = value;
                          });
                        },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _packagingState,
                  decoration: const InputDecoration(
                    labelText: 'Packaging condition',
                    prefixIcon: Icon(Icons.inventory_outlined),
                  ),
                  items: _packagingStates.map((state) {
                    return DropdownMenuItem<String>(
                      value: state,
                      child: Text(_packagingLabel(state)),
                    );
                  }).toList(),
                  onChanged: _isLoading
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _packagingState = value;
                          });
                        },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _allergensController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Allergens',
                    hintText: 'Example: milk, peanuts, wheat',
                    prefixIcon: Icon(
                      Icons.warning_amber_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Preparation time'),
                  subtitle: Text(_formatDateTime(_preparedAt)),
                  trailing: TextButton(
                    onPressed: _isLoading
                        ? null
                        : _selectPreparationTime,
                    child: const Text('Change'),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : _submitDonation,
                    child: _isLoading
                        ? const SizedBox(
                            width: 23,
                            height: 23,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            'Create Donation Passport',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}