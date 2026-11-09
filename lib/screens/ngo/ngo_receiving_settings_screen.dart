import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../location/location_picker_screen.dart';

class NgoReceivingSettingsScreen extends StatefulWidget {
  const NgoReceivingSettingsScreen({super.key});

  @override
  State<NgoReceivingSettingsScreen> createState() =>
      _NgoReceivingSettingsScreenState();
}

class _NgoReceivingSettingsScreenState
    extends State<NgoReceivingSettingsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _addressController =
      TextEditingController();

  final TextEditingController _cityController =
      TextEditingController();

  final TextEditingController _quantityController =
      TextEditingController();

  static const List<String> _categories = [
    'Cooked meal',
    'Bakery',
    'Fruits and vegetables',
    'Packaged food',
  ];

  final Set<String> _preferredCategories = <String>{};

  GeoPoint? _receivingLocation;

  String? _loadedUid;
  String? _loadError;
  String? _validationError;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isPickingLocation = false;

  bool get _isBusy =>
      _isLoading || _isSaving || _isPickingLocation;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _cityController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  String _readText(dynamic value) {
    return value is String ? value : '';
  }

  Future<void> _loadSettings() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      if (uid == null) {
        throw StateError('Please log in with your NGO account.');
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));

      if (!mounted) {
        return;
      }

      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError(
          'Your account changed. Please reopen this screen.',
        );
      }

      final data = snapshot.data();

      if (data == null ||
          data['role'] != 'ngo' ||
          data['isActive'] == false) {
        throw StateError('An active NGO profile is required.');
      }

      final rawSettings = data['ngoReceivingProfile'];

      final Map<String, dynamic>? settings =
          rawSettings is Map<String, dynamic>
              ? rawSettings
              : null;

      _addressController.text =
          _readText(settings?['address']);

      _cityController.text =
          _readText(settings?['city']);

      final Object? quantity = settings?['requiredQuantity'];

      _quantityController.text =
          quantity is int && quantity > 0 ? '$quantity' : '';

      final Object? location = settings?['location'];

      _receivingLocation =
          location is GeoPoint ? location : null;

      _preferredCategories.clear();

      final Object? preferences =
          settings?['preferredFoodCategories'];

      if (preferences is List) {
        for (final category in preferences) {
          if (category is String &&
              _categories.contains(category)) {
            _preferredCategories.add(category);
          }
        }
      }

      _loadedUid = uid;
    } catch (exception, stackTrace) {
      debugPrint('Loading NGO settings failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _loadError = exception is StateError
              ? exception.message.toString()
              : 'Unable to load NGO settings. '
                  'Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
            initialLocation: _receivingLocation,
            locateOnOpen: useCurrentLocation,
          ),
        ),
      );

      if (!mounted || point == null) {
        return;
      }

      setState(() {
        _receivingLocation = point;
        _validationError = null;
      });
    } catch (exception, stackTrace) {
      debugPrint('NGO location picker failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showMessage(
          'Unable to open the location picker.',
          isError: true,
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

  Future<void> _saveSettings() async {
    if (_isBusy) {
      return;
    }

    final validForm = _formKey.currentState?.validate() ?? false;
    final location = _receivingLocation;

    String? validationError;

    if (location == null) {
      validationError = 'Please select the NGO receiving point.';
    } else if (_preferredCategories.isEmpty) {
      validationError =
          'Select at least one preferred food category.';
    }

    setState(() {
      _validationError = validationError;
    });

    if (!validForm || validationError != null || location == null) {
      return;
    }

    final uid = _loadedUid;

    if (uid == null ||
        FirebaseAuth.instance.currentUser?.uid != uid) {
      _showMessage(
        'Your account changed. Please reopen this screen.',
        isError: true,
      );
      return;
    }

    final requiredQuantity = int.tryParse(
      _quantityController.text.trim(),
    );

    if (requiredQuantity == null || requiredQuantity <= 0) {
      return;
    }

    FocusScope.of(context).unfocus();

    final selectedCategories = _categories
        .where(_preferredCategories.contains)
        .toList();

    final settings = <String, dynamic>{
      'address': _addressController.text.trim(),
      'city': _cityController.text
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase(),
      'location': location,
      'requiredQuantity': requiredQuantity,
      'preferredFoodCategories': selectedCategories,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    setState(() {
      _isSaving = true;
    });

    try {
      final reference = FirebaseFirestore.instance
          .collection('users')
          .doc(uid);

      await FirebaseFirestore.instance.runTransaction<void>(
        (transaction) async {
          final snapshot = await transaction.get(reference);
          final profile = snapshot.data();

          if (FirebaseAuth.instance.currentUser?.uid != uid) {
            throw StateError(
              'Your account changed. Please start again.',
            );
          }

          if (profile == null ||
              profile['role'] != 'ngo' ||
              profile['isActive'] == false) {
            throw StateError(
              'An active NGO profile is required.',
            );
          }

          transaction.update(reference, {
            'ngoReceivingProfile': settings,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        },
      );

      if (!mounted ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }

      _showMessage('NGO receiving settings saved.');
    } catch (exception, stackTrace) {
      debugPrint('Saving NGO settings failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }

      final String message;

      if (exception is StateError) {
        message = exception.message.toString();
      } else if (exception is FirebaseException &&
          exception.code == 'permission-denied') {
        message =
            'Firestore denied this update. '
            'Publish the updated user-profile rules below.';
      } else {
        message =
            'Unable to confirm the save. '
            'Reopen settings to check the saved values.';
      }

      _showMessage(message, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? Colors.red.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_isSaving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('NGO receiving settings'),
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _loadError!,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadSettings,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Set the destination where volunteers '
                              'should deliver donations to your NGO.',
                            ),
                            const SizedBox(height: 20),

                            TextFormField(
                              controller: _addressController,
                              enabled: !_isBusy,
                              minLines: 2,
                              maxLines: 3,
                              maxLength: 300,
                              decoration: const InputDecoration(
                                labelText:
                                    'Receiving address / landmark',
                                prefixIcon:
                                    Icon(Icons.place_outlined),
                              ),
                              validator: (value) {
                                final text = value?.trim() ?? '';

                                return text.isEmpty ||
                                        text.length > 300
                                    ? 'Enter an address of '
                                        '1–300 characters'
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
                                prefixIcon: Icon(
                                  Icons.location_city_outlined,
                                ),
                              ),
                              validator: (value) {
                                final text = value?.trim() ?? '';

                                return text.isEmpty ||
                                        text.length > 80
                                    ? 'Enter a city of 1–80 characters'
                                    : null;
                              },
                            ),
                            const SizedBox(height: 12),

                            OutlinedButton.icon(
                              onPressed: _isBusy
                                  ? null
                                  : () => _pickLocation(
                                        useCurrentLocation: true,
                                      ),
                              icon: const Icon(Icons.my_location),
                              label:
                                  const Text('Use current location'),
                            ),
                            const SizedBox(height: 8),

                            OutlinedButton.icon(
                              onPressed: _isBusy
                                  ? null
                                  : () => _pickLocation(
                                        useCurrentLocation: false,
                                      ),
                              icon: const Icon(Icons.map_outlined),
                              label: Text(
                                _receivingLocation == null
                                    ? 'Choose receiving point on map'
                                    : 'View or change receiving point',
                              ),
                            ),

                            if (_receivingLocation != null)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text(
                                  'Receiving point selected. '
                                  'Ensure the address matches this point.',
                                  style: TextStyle(
                                    color: Color(0xFF356B4D),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),

                            Text(
                              'Donation requirements',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge,
                            ),
                            const SizedBox(height: 8),

                            const Text(
                              'These preferences will support matching. '
                              'You must still confirm capacity and '
                              'pickup arrangements for each claim.',
                            ),
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _quantityController,
                              enabled: !_isBusy,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText:
                                    'Current required portions/packets',
                                prefixIcon:
                                    Icon(Icons.inventory_2_outlined),
                              ),
                              validator: (value) {
                                final quantity = int.tryParse(
                                  value?.trim() ?? '',
                                );

                                return quantity == null ||
                                        quantity <= 0
                                    ? 'Enter a positive whole number'
                                    : null;
                              },
                            ),
                            const SizedBox(height: 20),

                            const Text(
                              'Preferred food categories',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            for (final category in _categories)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(category),
                                value: _preferredCategories
                                    .contains(category),
                                onChanged: _isBusy
                                    ? null
                                    : (selected) {
                                        setState(() {
                                          if (selected == true) {
                                            _preferredCategories
                                                .add(category);
                                          } else {
                                            _preferredCategories
                                                .remove(category);
                                          }
                                        });
                                      },
                              ),

                            if (_validationError != null)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 12),
                                child: Text(
                                  _validationError!,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ),

                            const SizedBox(height: 20),

                            FilledButton.icon(
                              onPressed:
                                  _isBusy ? null : _saveSettings,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                _isSaving
                                    ? 'Saving...'
                                    : 'Save receiving settings',
                              ),
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