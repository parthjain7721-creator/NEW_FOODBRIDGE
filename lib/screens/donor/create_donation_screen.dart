import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/donation_model.dart';
import '../../services/eligibility_service.dart';
import '../../services/firestore_service.dart';
import '../location/location_picker_screen.dart';
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

  GeoPoint? _pickupLocation;
  String? _locationError;

  bool _isLoading = false;
  bool _isPickingLocation = false;

  bool get _isBusy => _isLoading || _isPickingLocation;

  @override
  void dispose() {
    _quantityController.dispose();
    _allergensController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _pickLocation({
    required bool useCurrentLocation,
  }) async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isPickingLocation = true;
    });

    try {
      final point = await Navigator.of(context).push<GeoPoint>(
        MaterialPageRoute<GeoPoint>(
          builder: (_) => LocationPickerScreen(
            initialLocation: _pickupLocation,
            locateOnOpen: useCurrentLocation,
          ),
        ),
      );

      if (!mounted || point == null) {
        return;
      }

      setState(() {
        _pickupLocation = point;
        _locationError = null;
      });
    } catch (exception, stackTrace) {
      debugPrint('Opening location picker failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showMessage(
          'Unable to open the location picker. Please try again.',
          Colors.red.shade700,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingLocation = false;
        });
      }
    }
  }

  Future<void> _selectPreparationTime() async {
    if (_isBusy) {
      return;
    }

    final now = DateTime.now();
    final earliest = now.subtract(const Duration(days: 30));

    final initial = _preparedAt.isBefore(earliest)
        ? earliest
        : _preparedAt.isAfter(now)
            ? now
            : _preparedAt;

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: now,
    );

    if (selectedDate == null || !mounted) {
      return;
    }

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_preparedAt),
    );

    if (selectedTime == null || !mounted) {
      return;
    }

    final selected = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    if (selected.isAfter(DateTime.now())) {
      _showMessage(
        'Preparation time cannot be in the future.',
        Colors.orange.shade800,
      );
      return;
    }

    setState(() {
      _preparedAt = selected;
    });
  }

  Future<void> _submitDonation() async {
    if (_isBusy) {
      return;
    }

    final validForm = _formKey.currentState?.validate() ?? false;
    final point = _pickupLocation;

    setState(() {
      _locationError =
          point == null ? 'Please select a pickup location.' : null;
    });

    if (!validForm || point == null) {
      return;
    }

    FocusScope.of(context).unfocus();

    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      _showMessage(
        'Your login session has expired. Please log in again.',
        Colors.red.shade700,
      );
      return;
    }

    final quantity = int.tryParse(
      _quantityController.text.trim(),
    );

    if (quantity == null || quantity <= 0) {
      return;
    }

    final now = DateTime.now();

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

      final draft = DonationModel(
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
        pickupLocation: point,
      );

      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError(
          'Your account changed. Please start again.',
        );
      }

      final donationId =
          await _firestoreService.createDonation(draft);

      if (!mounted ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }

      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => DonationPassportScreen(
            donation: draft.withId(donationId),
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
                'Check that the pickup-location rules are published.'
            : 'Unable to confirm donation creation. '
                'Check donation history before retrying. '
                '(${exception.code})',
        Colors.red.shade700,
      );
    } on StateError catch (exception) {
      if (mounted &&
          FirebaseAuth.instance.currentUser?.uid == uid) {
        _showMessage(
          exception.message.toString(),
          Colors.red.shade700,
        );
      }
    } catch (exception, stackTrace) {
      debugPrint('Donation creation failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted &&
          FirebaseAuth.instance.currentUser?.uid == uid) {
        _showMessage(
          'Unable to confirm donation creation. '
          'Check donation history before retrying.',
          Colors.red.shade700,
        );
      }
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
      default:
        return 'Unknown';
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
    final local = value.toLocal();

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
      onChanged: _isBusy
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
                    enabled: !_isBusy,
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
                    enabled: !_isBusy,
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
                          _isBusy ? null : _selectPreparationTime,
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
                    'Enter the collection address and city, then '
                    'confirm its point on the map. You do not '
                    'need to know your coordinates.',
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _addressController,
                    enabled: !_isBusy,
                    minLines: 2,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Pickup address / landmark',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                    validator: (value) {
                      final address = value?.trim() ?? '';

                      return address.isEmpty || address.length > 300
                          ? 'Enter an address of 1–300 characters'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _cityController,
                    enabled: !_isBusy,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      hintText: 'Use consistent spelling',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                    validator: (value) {
                      final city = value?.trim() ?? '';

                      return city.isEmpty || city.length > 80
                          ? 'Enter a city of 1–80 characters'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isBusy
                          ? null
                          : () => _pickLocation(
                                useCurrentLocation: true,
                              ),
                      icon: const Icon(Icons.my_location),
                      label: const Text('Use my current location'),
                    ),
                  ),
                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isBusy
                          ? null
                          : () => _pickLocation(
                                useCurrentLocation: false,
                              ),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(
                        _pickupLocation == null
                            ? 'Choose pickup point on map'
                            : 'View or change pickup point',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_pickupLocation != null)
                    const Text(
                      'Pickup point selected and confirmed. '
                      'Make sure the address and city describe '
                      'the same collection point.',
                      style: TextStyle(
                        color: Color(0xFF356B4D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                  if (_locationError != null)
                    Text(
                      _locationError!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                      ),
                    ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isBusy ? null : _submitDonation,
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