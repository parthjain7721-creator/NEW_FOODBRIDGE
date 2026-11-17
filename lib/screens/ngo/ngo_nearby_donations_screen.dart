import 'dart:async';


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';


import '../../models/ngo_need_model.dart';
import '../../services/matching_service.dart';
import '../../services/route_service.dart';
import 'donation_details_screen.dart';
import 'ngo_receiving_settings_screen.dart';
import 'ngo_route_preview_screen.dart';


class NgoNearbyDonationsScreen extends StatefulWidget {
  const NgoNearbyDonationsScreen({super.key});


  @override
  State<NgoNearbyDonationsScreen> createState() =>
      _NgoNearbyDonationsScreenState();
}


class _NgoNearbyDonationsScreenState
    extends State<NgoNearbyDonationsScreen> {
  static const double _radiusMetres = 10000;
  static const int _maximumRouteCalculations = 10;


  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final RouteService _routeService = RouteService();


  Stream<QuerySnapshot<Map<String, dynamic>>>? _donationsStream;


  StreamSubscription<User?>? _authSubscription;
  Timer? _timer;


  String? _uid;
  String? _loadError;


  GeoPoint? _receivingLocation;
  String _receivingAddress = '';
  int _requiredQuantity = 0;


  final Set<String> _preferredCategories = <String>{};


  final Map<String, MatchPriorityResult?> _matchResults =
      <String, MatchPriorityResult?>{};


  final Set<String> _calculatingMatches = <String>{};


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
      _requiredQuantity = 0;
      _preferredCategories.clear();
      _matchResults.clear();
      _calculatingMatches.clear();
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
      

      final NgoNeedModel ngoNeed =
          NgoNeedModel.fromMap(
        settings ?? <String, dynamic>{},
      );


      setState(() {
        _receivingLocation =
            location is GeoPoint ? location : null;


        _receivingAddress = _text(
          settings?['address'],
          'Receiving address not recorded',
        );


        _requiredQuantity = ngoNeed.requiredQuantity;


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


  Future<void> _openRoutePreview(_NearbyDonation item) async {
    if (_isOpeningScreen ||
        _uid == null ||
        _auth.currentUser?.uid != _uid) {
      return;
    }


    final receiving = _receivingLocation;


    if (receiving == null) {
      return;
    }


    final data = item.document.data();
    final Object? pickup = data['pickupLocation'];


    if (pickup is! GeoPoint) {
      return;
    }


    setState(() {
      _isOpeningScreen = true;
    });


    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => NgoRoutePreviewScreen(
            donationId: item.document.id,
            donationTitle: _text(
              data['foodCategory'],
              'Food donation',
            ),
            pickupLocation: pickup,
            pickupAddress: _text(
              data['pickupAddress'],
              'Pickup address not recorded',
            ),
            receivingLocation: receiving,
            receivingAddress: _receivingAddress,
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


  void _startMatchEvaluations(
    List<_NearbyDonation> nearby,
  ) {
    final receiving = _receivingLocation;


    if (receiving == null) {
      return;
    }


    final int version = _loadVersion;


    final List<_NearbyDonation> donationsToEvaluate =
        nearby.take(_maximumRouteCalculations).toList();


    for (final item in donationsToEvaluate) {
      final String donationId = item.document.id;


      if (_matchResults.containsKey(donationId) ||
          _calculatingMatches.contains(donationId)) {
        continue;
      }


      _calculatingMatches.add(donationId);


      Future<void>(() async {
        final data = item.document.data();


        final Object? pickup = data['pickupLocation'];
        final DateTime? deadline = _date(data['pickupDeadline']);


        if (pickup is! GeoPoint || deadline == null) {
          if (mounted && version == _loadVersion) {
            setState(() {
              _calculatingMatches.remove(donationId);
              _matchResults[donationId] = null;
            });
          }


          return;
        }


        try {
          final FoodBridgeRoute route =
              await _routeService.getDrivingRoute(
            pickup: pickup,
            destination: receiving,
            startingPoint: receiving,
          );


          final NgoNeedModel ngoNeed = NgoNeedModel(
            requiredQuantity: _requiredQuantity,
            preferredFoodCategories: _preferredCategories,
          );


          final MatchPriorityResult result =
              MatchingService.evaluate(
            foodCategory: _text(
              data['foodCategory'],
              '',
            ),
            quantity:
                data['quantity'] is num ? data['quantity'] : 0,
            pickupDeadline: deadline,
            now: DateTime.now(),
            ngoNeed: ngoNeed,
            route: route,
          );


          if (mounted && version == _loadVersion) {
            setState(() {
              _matchResults[donationId] = result;
            });
          }
        } catch (exception, stackTrace) {
          debugPrint(
            'Match Priority route calculation failed for '
            '$donationId: $exception',
          );
          debugPrintStack(stackTrace: stackTrace);


          if (mounted && version == _loadVersion) {
            setState(() {
              _matchResults[donationId] = null;
            });
          }
        } finally {
          if (mounted && version == _loadVersion) {
            setState(() {
              _calculatingMatches.remove(donationId);
            });
          }
        }
      });
    }
  }


  List<_NearbyDonation> _rankNearby(
    List<_NearbyDonation> nearby,
  ) {
    final ranked = List<_NearbyDonation>.from(nearby);


    ranked.sort((first, second) {
      final MatchPriorityResult? firstResult =
          _matchResults[first.document.id];


      final MatchPriorityResult? secondResult =
          _matchResults[second.document.id];


      final bool firstEvaluated = firstResult != null;
      final bool secondEvaluated = secondResult != null;


      final bool firstFeasible =
          firstEvaluated && firstResult.isFeasible;


      final bool secondFeasible =
          secondEvaluated && secondResult.isFeasible;


      if (firstFeasible != secondFeasible) {
        return firstFeasible ? -1 : 1;
      }


      if (firstFeasible && secondFeasible) {
        final int comparison = secondResult.totalScore
            .compareTo(firstResult.totalScore);


        if (comparison != 0) {
          return comparison;
        }
      }


      final int distanceComparison =
          first.distanceMetres.compareTo(
        second.distanceMetres,
      );


      return distanceComparison != 0
          ? distanceComparison
          : first.document.id.compareTo(second.document.id);
    });


    return ranked;
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
              'Match Priority ranks feasible NGO round trips using '
              'urgency, NGO need, route feasibility, and estimated '
              'driving time. It does not automatically claim '
              'donations or assign volunteers.',
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


  Widget _matchPriorityCard(
    _NearbyDonation item,
    MatchPriorityResult? result,
  ) {
    final String donationId = item.document.id;


    if (_calculatingMatches.contains(donationId)) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: const Text(
                'Calculating road-route Match Priority...',
              ),
            ),
          ],
        ),
      );
    }


    if (result == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'Road-route Match Priority could not be calculated. '
          'Use road-route preview to review this donation.',
          style: TextStyle(
            color: Colors.orange.shade900,
          ),
        ),
      );
    }


    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: result.isFeasible
            ? Colors.green.shade50
            : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.isFeasible
                ? 'Match Priority: ${result.totalScore}'
                : 'Not feasible for NGO round trip',
            style: TextStyle(
              color: result.isFeasible
                  ? Colors.green.shade800
                  : Colors.red.shade800,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Urgency: ${result.urgencyScore} • '
            'NGO need: ${result.ngoNeedScore} • '
            'Feasibility: ${result.pickupFeasibilityScore} • '
            'Travel-time deduction: '
            '${result.travelTimeDeduction}',
          ),
          const SizedBox(height: 6),
          Text(
            'NGO round trip: '
            '${result.routeDistanceKilometres.toStringAsFixed(2)} km • '
            '${result.estimatedMinutes} min estimated driving time',
          ),
          const SizedBox(height: 6),
          Text(result.explanation),
        ],
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


    final MatchPriorityResult? result =
        _matchResults[document.id];


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
            _matchPriorityCard(item, result),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isOpeningScreen
                  ? null
                  : () => _openDonation(document.id),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('View donation details'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isOpeningScreen
                  ? null
                  : () => _openRoutePreview(item),
              icon: const Icon(Icons.route_outlined),
              label: const Text('Preview road route'),
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


                          Future<void>.microtask(() {
                            _startMatchEvaluations(nearby);
                          });


                          final ranked = _rankNearby(nearby);


                          final contentCount =
                              ranked.isEmpty ? 1 : ranked.length;


                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: contentCount + 1,
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return _header(ranked.length);
                              }


                              if (ranked.isEmpty) {
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
                                ranked[index - 1],
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