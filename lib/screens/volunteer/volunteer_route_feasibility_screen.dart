import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../services/route_service.dart';

class VolunteerRouteFeasibilityScreen extends StatefulWidget {
  final String donationId;
  final String donationTitle;
  final GeoPoint pickupLocation;
  final String pickupAddress;
  final GeoPoint receivingLocation;
  final String receivingAddress;
  final DateTime? pickupDeadline;

  const VolunteerRouteFeasibilityScreen({
    super.key,
    required this.donationId,
    required this.donationTitle,
    required this.pickupLocation,
    required this.pickupAddress,
    required this.receivingLocation,
    required this.receivingAddress,
    required this.pickupDeadline,
  });

  @override
  State<VolunteerRouteFeasibilityScreen> createState() =>
      _VolunteerRouteFeasibilityScreenState();
}

class _VolunteerRouteFeasibilityScreenState
    extends State<VolunteerRouteFeasibilityScreen> {
  final RouteService _routeService = RouteService();
  final MapController _mapController = MapController();

  FoodBridgeRoute? _route;
  String? _feasibilityError;
  bool _isLoadingRoute = false;

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw StateError(
        'Location services are disabled. Enable location services '
        'to check route feasibility.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw StateError(
        'Location permission is required to calculate a route from '
        'your current location.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission is permanently denied. Enable location '
        'permission for FoodBridge in your device settings.',
      );
    }

    return true;
  }

  Future<Position> _getCurrentPosition() async {
    await _ensureLocationPermission();

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  Future<void> _checkFeasibility() async {
    if (_isLoadingRoute) {
      return;
    }

    setState(() {
      _isLoadingRoute = true;
      _feasibilityError = null;
    });

    try {
      final position = await _getCurrentPosition();

      final route = await _routeService.getDrivingRoute(
        pickup: widget.pickupLocation,
        destination: widget.receivingLocation,
        startingPoint: GeoPoint(
          position.latitude,
          position.longitude,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _route = route;
      });

      _fitRoute(route);
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _route = null;
        _feasibilityError =
            'Finding your location or calculating the route timed out. '
            'Please try again.';
      });
    } catch (exception) {
      if (!mounted) return;

      setState(() {
        _route = null;
        _feasibilityError = exception is StateError
            ? exception.message
            : 'Unable to calculate route feasibility. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
        });
      }
    }
  }

  void _fitRoute(FoodBridgeRoute route) {
    final points = route.points;

    if (points.length < 2) {
      return;
    }

    double minimumLatitude = points.first.latitude;
    double maximumLatitude = points.first.latitude;
    double minimumLongitude = points.first.longitude;
    double maximumLongitude = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minimumLatitude) {
        minimumLatitude = point.latitude;
      }

      if (point.latitude > maximumLatitude) {
        maximumLatitude = point.latitude;
      }

      if (point.longitude < minimumLongitude) {
        minimumLongitude = point.longitude;
      }

      if (point.longitude > maximumLongitude) {
        maximumLongitude = point.longitude;
      }
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minimumLatitude, minimumLongitude),
          LatLng(maximumLatitude, maximumLongitude),
        ),
        padding: const EdgeInsets.fromLTRB(
          48,
          96,
          48,
          96,
        ),
      ),
    );
  }

  String _distanceText(FoodBridgeRoute route) {
    final kilometres = route.distanceKilometres;

    if (kilometres < 1) {
      return '${route.distanceMetres.round()} m';
    }

    return '${kilometres.toStringAsFixed(1)} km';
  }

  String _durationText(FoodBridgeRoute route) {
    final minutes = route.estimatedMinutes;

    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (remainingMinutes == 0) {
      return '$hours hr';
    }

    return '$hours hr $remainingMinutes min';
  }

  Widget _locationCard({
    required String title,
    required String address,
    required String coordinates,
    required Color colour,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          Icons.location_on_outlined,
          color: colour,
        ),
        title: Text(title),
        subtitle: Text('$address\n$coordinates'),
        isThreeLine: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pickup = widget.pickupLocation;
    final receiving = widget.receivingLocation;
    final route = _route;

    final pickupPoint = LatLng(
      pickup.latitude,
      pickup.longitude,
    );

    final receivingPoint = LatLng(
      receiving.latitude,
      receiving.longitude,
    );

    final deadline = widget.pickupDeadline;
    final estimatedCompletion =
        route == null ? null : DateTime.now().add(
      Duration(
        seconds: route.durationSeconds.round(),
      ),
    );

    final feasible = route != null &&
        deadline != null &&
        estimatedCompletion != null &&
        estimatedCompletion.isBefore(deadline);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route feasibility'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.donationTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This check calculates a driving route from your '
                        'current location to the donor pickup point, then '
                        'to the NGO receiving point.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your current location is used only for this route '
                        'request and is sent to OpenRouteService when you '
                        'start the check. The result is an estimate and '
                        'does not assign you to the task, guarantee arrival, '
                        'or certify food safety.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              _locationCard(
                title: 'Donor pickup point',
                address: widget.pickupAddress,
                coordinates:
                    '${pickup.latitude.toStringAsFixed(6)}, '
                    '${pickup.longitude.toStringAsFixed(6)}',
                colour: Colors.orange.shade700,
              ),
              _locationCard(
                title: 'NGO receiving point',
                address: widget.receivingAddress,
                coordinates:
                    '${receiving.latitude.toStringAsFixed(6)}, '
                    '${receiving.longitude.toStringAsFixed(6)}',
                colour: Colors.green.shade700,
              ),
              if (route != null) ...[
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated route',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total road distance: '
                          '${_distanceText(route)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Estimated driving time: '
                          '${_durationText(route)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Estimated completion time: '
                          '${_formatTime(estimatedCompletion!)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          deadline == null
                              ? 'Pickup deadline is not recorded.'
                              : 'Pickup deadline: '
                                  '${_formatTime(deadline)}',
                        ),
                        const SizedBox(height: 12),
                        if (deadline == null)
                          _notice(
                            'A pickup deadline is not recorded, so route '
                            'feasibility cannot be assessed.',
                            Colors.orange.shade900,
                          )
                        else if (feasible)
                          _notice(
                            'The estimated completion time is before the '
                            'pickup deadline. This is an estimate only.',
                            Colors.green.shade700,
                          )
                        else
                          _notice(
                            'The estimated completion time is after the '
                            'pickup deadline. Do not rely on this route '
                            'to complete the pickup on time.',
                            Colors.red.shade700,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_feasibilityError != null) ...[
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_feasibilityError!),
                  ),
                ),
              ],
              FilledButton.icon(
                onPressed: _isLoadingRoute ? null : _checkFeasibility,
                icon: _isLoadingRoute
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.route_outlined),
                label: Text(
                  route == null
                      ? 'Check route feasibility'
                      : 'Recalculate route',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: route == null ? 220 : 360,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: pickupPoint,
                      initialZoom: 12,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.foodbridge',
                      ),
                      if (route != null)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: route.points,
                              strokeWidth: 5,
                              color: Theme.of(context).primaryColor,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: pickupPoint,
                            width: 44,
                            height: 44,
                            child: const Icon(
                              Icons.storefront_outlined,
                              color: Colors.orange,
                              size: 36,
                            ),
                          ),
                          Marker(
                            point: receivingPoint,
                            width: 44,
                            height: 44,
                            child: const Icon(
                              Icons.volunteer_activism_outlined,
                              color: Colors.green,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(
                            'OpenStreetMap contributors',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Map data © OpenStreetMap contributors.',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notice(String message, Color colour) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: colour,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}