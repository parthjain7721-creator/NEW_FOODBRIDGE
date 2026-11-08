import 'package:cloud_firestore/cloud_firestore.dart';
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

  final TextEditingController _addressController =
      TextEditingController();

  final TextEditingController _cityController =
      TextEditingController();

  final TextEditingController _latitudeController =
      TextEditingController();

  final TextEditingController _longitudeController =
      TextEditingController();

  static const List<String> _foodCategories = [
    'Cooked meal',
    'Bakery',
    'Fruits and vegetables',
    'Packaged food',
  ];

  static const List<String> _storageMethods = [
    'room_temperature',
    'refrigerated',
    'frozen',
    'unknown',
  ];

  static const List<String> _packagingStates = [
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
    _addressController.dispose();
    _cityController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _selectPreparationTime() async {
    if (_isLoading) {
      return;
    }

    final DateTime now = DateTime.now();

    final DateTime earliestDate =
        now.subtract(const Duration(days: 30));

    final DateTime initialDate = _preparedAt.isBefore(earliestDate)
        ? earliestDate
        : _preparedAt.isAfter(now)
            ? now
            : _preparedAt;

    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: earliestDate,
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

    if (selectedDateTime.isAfter(DateTime.now())) {
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

  String? _validateCoordinate(
    String? value, {
    required bool latitude,
  }) {
    final double? coordinate = double.tryParse(
      value?.trim() ?? '',
    );

    final double minimum = latitude ? -90 : -180;
    final double maximum = latitude ? 90 : 180;

    if (coordinate == null ||
        !coordinate.isFinite ||
        coordinate < minimum ||
        coordinate > maximum) {
      return latitude
          ? 'Enter latitude from -90 to 90'
          : 'Enter longitude from -180 to 180';
    }

    return null;
  }

  Future<void> _submitDonation() async {
    if (_isLoading ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      _showMessage(
        'Your login session has expired. Please log in again.',
        Colors.red.shade700,
      );
      return;
    }

    final int? quantity = int.tryParse(
      _quantityController.text.trim(),
    );

    final double? latitude = double.tryParse(
      _latitudeController.text.trim(),
    );

    final double? longitude = double.tryParse(
      _longitudeController.text.trim(),
    );

    if (quantity == null ||
        quantity <= 0 ||
        latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      _showMessage(
        'Check the quantity and pickup coordinates.',
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

    setState(() {
      _isLoading = true;
    });

    try {
      final EligibilityResult eligibility =
          EligibilityService.calculate(
        preparedAt: _preparedAt,
        now: now,
        foodCategory: _foodCategory,
        storageMethod: _storageMethod,
        packagingState: _packagingState,
      );

      final DonationModel draftDonation = DonationModel(
        id: '',
        donorId: uid,
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
        pickupAddress: _addressController.text.trim(),
        pickupCity: _cityController.text
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ')
            .toLowerCase(),
        pickupLocation: GeoPoint(latitude, longitude),
      );

      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError(
          'Your account changed. Please start again.',
        );
      }

      final String donationId =
          await _firestoreService.createDonation(draftDonation);

      if (!mounted ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }

      final DonationModel savedDonation =
          draftDonation.withId(donationId);

      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => DonationPassportScreen(
            donation: savedDonation,
            explanation: eligibility.explanation,
          ),
        ),
      );
    } on FirebaseException catch (exception, stackTrace) {
      debugPrint(
        'Donation creation failed: '
        '${exception.code} - ${exception.message}',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }

      _showMessage(
        exception.code == 'permission-denied'
            ? 'Firestore denied donation creation. '
                'Publish the updated donation-creation rules '
                'that allow and validate pickup location.'
            : 'Unable to confirm donation creation. '
                'Check donation history before retrying. '
                '(${exception.code})',
        Colors.red.shade700,
      );
    } on StateError catch (exception) {
      if (!mounted) {
        return;
      }

      _showMessage(
        exception.message.toString(),
        Colors.red.shade700,
      );
    } catch (exception, stackTrace) {
      debugPrint('Unexpected donation creation error: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }

      _showMessage(
        'Unable to confirm donation creation. '
        'Check donation history before retrying.',
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
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
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

    String two(int number) => number.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _dropdown({
    required String value,
    required String label,
    required IconData icon,
    required List<String> options,
    required String Function(String) optionLabel,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
      items: options.map((option) {
        return DropdownMenuItem<String>(
          value: option,
          child: Text(optionLabel(option)),
        );
      }).toList(),
      onChanged: _isLoading
          ? null
          : (selected) {
              if (selected != null) {
                onChanged(selected);
              }
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_isLoading,
      child: Scaffold(
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
                  const Text(
                    'FoodBridge calculates a transparent rescue status '
                    'from your declarations.',
                  ),
                  const SizedBox(height: 28),

                  _dropdown(
                    value: _foodCategory,
                    label: 'Food category',
                    icon: Icons.restaurant_outlined,
                    options: _foodCategories,
                    optionLabel: (value) => value,
                    onChanged: (value) {
                      setState(() {
                        _foodCategory = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _quantityController,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      hintText: 'Number of portions or packets',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    validator: (value) {
                      final quantity = int.tryParse(
                        value?.trim() ?? '',
                      );

                      return quantity == null || quantity <= 0
                          ? 'Enter a valid positive whole number'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),

                  _dropdown(
                    value: _storageMethod,
                    label: 'Storage method',
                    icon: Icons.kitchen_outlined,
                    options: _storageMethods,
                    optionLabel: _storageLabel,
                    onChanged: (value) {
                      setState(() {
                        _storageMethod = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  _dropdown(
                    value: _packagingState,
                    label: 'Packaging condition',
                    icon: Icons.inventory_outlined,
                    options: _packagingStates,
                    optionLabel: _packagingLabel,
                    onChanged: (value) {
                      setState(() {
                        _packagingState = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _allergensController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Allergens',
                      hintText: 'Example: milk, peanuts, wheat',
                      prefixIcon: Icon(Icons.warning_amber_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('Preparation time'),
                    subtitle: Text(_formatDateTime(_preparedAt)),
                    trailing: TextButton(
                      onPressed:
                          _isLoading ? null : _selectPreparationTime,
                      child: const Text('Change'),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  Text(
                    'Pickup location',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the location where the volunteer '
                    'should collect this donation. Coordinates '
                    'must refer to that pickup point.',
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _addressController,
                    enabled: !_isLoading,
                    minLines: 2,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Pickup address / landmark',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                    validator: (value) {
                      final address = value?.trim() ?? '';

                      if (address.isEmpty || address.length > 300) {
                        return 'Enter an address of 1–300 characters';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _cityController,
                    enabled: !_isLoading,
                    maxLength: 80,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      hintText: 'Use consistent spelling',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                    validator: (value) {
                      final city = value?.trim() ?? '';

                      if (city.isEmpty || city.length > 80) {
                        return 'Enter a city of 1–80 characters';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _latitudeController,
                    enabled: !_isLoading,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Pickup latitude',
                      helperText: 'Decimal degrees, from -90 to 90',
                    ),
                    validator: (value) => _validateCoordinate(
                      value,
                      latitude: true,
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _longitudeController,
                    enabled: !_isLoading,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Pickup longitude',
                      helperText: 'Decimal degrees, from -180 to 180',
                    ),
                    validator: (value) => _validateCoordinate(
                      value,
                      latitude: false,
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text(
                    'For now, enter coordinates manually. '
                    'Address-to-coordinate lookup and map selection '
                    'are not implemented in this form.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          _isLoading ? null : _submitDonation,
                      child: _isLoading
                          ? const SizedBox(
                              width: 23,
                              height: 23,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('Create Donation Passport'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'FoodBridge records declarations and workflow '
                    'checks. It does not certify food safety.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}