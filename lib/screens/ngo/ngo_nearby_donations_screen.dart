import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'donation_details_screen.dart';
import 'ngo_receiving_settings_screen.dart';

class NgoNearbyDonationsScreen extends StatefulWidget {
  const NgoNearbyDonationsScreen({super.key});

  @override
  State<NgoNearbyDonationsScreen> createState() =>
      _NgoNearbyDonationsScreenState();
}

class _NgoNearbyDonationsScreenState
    extends State<NgoNearbyDonationsScreen> {
  static const double _radiusMetres = 10000;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _donationsStream;

  StreamSubscription<User?>? _authSubscription;
  Timer? _timer;

  String? _uid;
  String? _loadError;

  GeoPoint? _receivingLocation;
  String _receivingAddress = '';

  final Set<String> _preferredCategories = <String>{};

  bool _isLoading = true;
  bool _isOpeningScreen = false;

  int _loadVersion = 0;

  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();

    _uid = _auth.currentUser?.uid;
    _loadProfile();

    _authSubscription = _auth.authStateChanges().listen((user) {
      if (!mounted || user?.uid == _uid) {
        return;
      }

      _uid = user?.uid;
      _loadProfile();
    });

    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (mounted) {
          setState(() {
            _now = DateTime.now();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _loadVersion++;
    _timer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  String _text(dynamic value, String fallback) {
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : fallback;
  }

  DateTime? _date(dynamic value) {
    return value is Timestamp ? value.toDate() : null;
  }

  bool _loadStillCurrent(int version, String? uid) {
    return mounted &&
        version == _loadVersion &&
        _auth.currentUser?.uid == uid;
  }

  Future<void> _loadProfile() async {
    final int version = ++_loadVersion;
    final String? uid = _auth.currentUser?.uid;

    setState(() {
      _uid = uid;
      _isLoading = true;
      _loadError = null;
      _receivingLocation = null;
      _receivingAddress = '';
      _preferredCategories.clear();
      _donationsStream = null;
    });

    try {
      if (uid == null) {
        throw StateError('Please log in with your NGO account.');
      }

      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));

      if (!_loadStillCurrent(version, uid)) {
        return;
      }

      final profile = snapshot.data();

      if (profile == null ||
          profile['role'] != 'ngo' ||
          profile['isActive'] == false) {
        throw StateError('An active NGO profile is required.');
      }

      final Object? rawSettings = profile['ngoReceivingProfile'];

      final Map<String, dynamic>? settings =
          rawSettings is Map<String, dynamic>
              ? rawSettings
              : null;

      final Object? location = settings?['location'];

      setState(() {
        _receivingLocation =
            location is GeoPoint ? location : null;

        _receivingAddress = _text(
          settings?['address'],
          'Receiving address not recorded',
        );

        final Object? categories =
            settings?['preferredFoodCategories'];

        if (categories is List) {
          for (final category in categories) {
            if (category is String) {
              _preferredCategories.add(category);
            }
          }
        }

        if (_receivingLocation != null) {
          _donationsStream = _firestore
              .collection('donations')
              .where('status', isEqualTo: 'available')
              .snapshots();
        }

        _now = DateTime.now();
      });
    } catch (exception, stackTrace) {
      debugPrint('Nearby donation setup failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (_loadStillCurrent(version, uid)) {
        setState(() {
          _loadError = exception is StateError
              ? exception.message.toString()
              : 'Unable to load receiving settings. '
                  'Check your connection and account access.';
        });
      }
    } finally {
      if (_loadStillCurrent(version, uid)) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openReceivingSettings() async {
    if (_isOpeningScreen) {
      return;
    }

    setState(() {
      _isOpeningScreen = true;
    });

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const NgoReceivingSettingsScreen(),
        ),
      );

      if (mounted) {
        await _loadProfile();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningScreen = false;
        });
      }
    }
  }

  Future<void> _openDonation(String donationId) async {
    if (_isOpeningScreen ||
        _uid == null ||
        _auth.currentUser?.uid != _uid) {
      return;
    }

    setState(() {
      _isOpeningScreen = true;
    });

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DonationDetailsScreen(
            donationId: donationId,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningScreen = false;
          _now = DateTime.now();
        });
      }
    }
  }

  List<_NearbyDonation> _findNearby(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    final receiving = _receivingLocation;

    if (receiving == null) {
      return <_NearbyDonation>[];
    }

    final result = <_NearbyDonation>[];

    for (final document in documents) {
      final data = document.data();

      if (data['status'] != 'available' ||
          data['donorId'] == _uid) {
        continue;
      }

      if (data['eligibilityStatus'] != 'eligible' &&
          data['eligibilityStatus'] != 'urgent') {
        continue;
      }

      final deadline = _date(data['pickupDeadline']);

      if (deadline == null || !deadline.isAfter(_now)) {
        continue;
      }

      final Object? pickup = data['pickupLocation'];

      if (pickup is! GeoPoint) {
        continue;
      }

      final distanceMetres = Geolocator.distanceBetween(
        receiving.latitude,
        receiving.longitude,
        pickup.latitude,
        pickup.longitude,
      );

      if (!distanceMetres.isFinite ||
          distanceMetres > _radiusMetres) {
        continue;
      }

      result.add(
        _NearbyDonation(
          document: document,
          distanceMetres: distanceMetres,
        ),
      );
    }

    result.sort((first, second) {
      final comparison =
          first.distanceMetres.compareTo(second.distanceMetres);

      return comparison != 0
          ? comparison
          : first.document.id.compareTo(second.document.id);
    });

    return result;
  }

  String _quantity(dynamic value) {
    return value is num && value.isFinite && value > 0
        ? '$value portions/packets'
        : 'Quantity not recorded';
  }

  String _remaining(DateTime? deadline) {
    if (deadline == null) {
      return 'Deadline not recorded';
    }

    final remaining = deadline.difference(_now);

    if (remaining <= Duration.zero) {
      return 'Pickup window closed';
    }

    if (remaining.inMinutes == 0) {
      return 'Less than one minute remaining';
    }

    return '${remaining.inHours}h '
        '${remaining.inMinutes.remainder(60)}m remaining';
  }

  Widget _header(int count) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$count eligible donation(s) within 10 km',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('Receiving address: $_receivingAddress'),
            const SizedBox(height: 8),
            const Text(
              'Distance is measured from your saved NGO receiving '
              'point, not your phone’s current location.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Sorted by geographical distance. Road travel time '
              'and Match Priority are not calculated yet.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  _isOpeningScreen ? null : _openReceivingSettings,
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('Change receiving settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _donationCard(_NearbyDonation item) {
    final document = item.document;
    final data = document.data();

    final category = _text(
      data['foodCategory'],
      'Food donation',
    );

    final urgent = data['eligibilityStatus'] == 'urgent';
    final preferred = _preferredCategories.contains(category);
    final deadline = _date(data['pickupDeadline']);

    return Card(
      key: ValueKey('nearby-${document.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              category,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(_quantity(data['quantity'])),
            const SizedBox(height: 8),
            Text(
              '${(item.distanceMetres / 1000).toStringAsFixed(2)} km '
              'from NGO receiving point',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              urgent ? 'Urgent pickup' : 'Eligible for pickup',
              style: TextStyle(
                color: urgent
                    ? Colors.orange.shade900
                    : Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (preferred) ...[
              const SizedBox(height: 6),
              const Text('Matches a preferred food category'),
            ],
            const SizedBox(height: 8),
            Text(
              'Pickup address: '
              '${_text(data['pickupAddress'], 'Not recorded')}',
            ),
            const SizedBox(height: 8),
            Text(_remaining(deadline)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isOpeningScreen
                  ? null
                  : () => _openDonation(document.id),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('View donation details'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messagePanel({
    required String message,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _isOpeningScreen ? null : onPressed,
              child: Text(buttonLabel),
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
        title: const Text('Nearby donations'),
        actions: [
          IconButton(
            tooltip: 'Reload receiving settings and donations',
            onPressed: _isLoading || _isOpeningScreen
                ? null
                : _loadProfile,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? _messagePanel(
                    message: _loadError!,
                    buttonLabel: 'Try again',
                    onPressed: _loadProfile,
                  )
                : _receivingLocation == null
                    ? _messagePanel(
                        message:
                            'Set your NGO receiving location first '
                            'so FoodBridge can find nearby donations.',
                        buttonLabel: 'Set receiving location',
                        onPressed: _openReceivingSettings,
                      )
                    : StreamBuilder<
                        QuerySnapshot<Map<String, dynamic>>>(
                        key: ValueKey('nearby-stream-$_uid'),
                        stream: _donationsStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return _messagePanel(
                              message:
                                  'Unable to load available donations. '
                                  'Check your connection and NGO '
                                  'account access.',
                              buttonLabel: 'Try again',
                              onPressed: _loadProfile,
                            );
                          }

                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final nearby = _findNearby(
                            snapshot.data!.docs,
                          );

                          final contentCount =
                              nearby.isEmpty ? 1 : nearby.length;

                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: contentCount + 1,
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return _header(nearby.length);
                              }

                              if (nearby.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'No eligible donations with a saved '
                                    'pickup location are currently '
                                    'within 10 km of your receiving point.',
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              }

                              return _donationCard(
                                nearby[index - 1],
                              );
                            },
                          );
                        },
                      ),
      ),
    );
  }
}

class _NearbyDonation {
  final QueryDocumentSnapshot<Map<String, dynamic>> document;
  final double distanceMetres;

  const _NearbyDonation({
    required this.document,
    required this.distanceMetres,
  });
}