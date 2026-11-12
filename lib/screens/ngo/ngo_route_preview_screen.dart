import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/route_service.dart';

class NgoRoutePreviewScreen extends StatefulWidget {
  final String donationId;
  final String donationTitle;
  final GeoPoint pickupLocation;
  final String pickupAddress;
  final GeoPoint receivingLocation;
  final String receivingAddress;

  const NgoRoutePreviewScreen({
    super.key,
    required this.donationId,
    required this.donationTitle,
    required this.pickupLocation,
    required this.pickupAddress,
    required this.receivingLocation,
    required this.receivingAddress,
  });

  @override
  State<NgoRoutePreviewScreen> createState() =>
      _NgoRoutePreviewScreenState();
}

class _NgoRoutePreviewScreenState extends State<NgoRoutePreviewScreen> {
  final RouteService _routeService = RouteService();
  final MapController _mapController = MapController();

  FoodBridgeRoute? _route;
  String? _routeError;
  bool _isLoadingRoute = false;

  Future<void> _loadRoute() async {
    if (_isLoadingRoute) {
      return;
    }

    setState(() {
      _isLoadingRoute = true;
      _routeError = null;
    });

    try {
      final route = await _routeService.getDrivingRoute(
        pickup: widget.pickupLocation,
        destination: widget.receivingLocation,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _route = route;
      });

      _fitRoute(route);
    } catch (exception) {
      if (!mounted) {
        return;
      }

      setState(() {
        _route = null;
        _routeError = exception is StateError
            ? exception.message
            : 'Unable to load the road route. Please try again.';
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

    final bounds = LatLngBounds(
      LatLng(minimumLatitude, minimumLongitude),
      LatLng(maximumLatitude, maximumLongitude),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
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
        subtitle: Text(
          '$address\n$coordinates',
        ),
        isThreeLine: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pickup = widget.pickupLocation;
    final receiving = widget.receivingLocation;

    final pickupPoint = LatLng(
      pickup.latitude,
      pickup.longitude,
    );

    final receivingPoint = LatLng(
      receiving.latitude,
      receiving.longitude,
    );

    final route = _route;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Road route preview'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'This preview calculates a driving route '
                              'between the donor pickup point and your '
                              'saved NGO receiving point.',
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'The selected locations are sent to '
                              'OpenRouteService when you load the route. '
                              'The result is an estimate and does not '
                              'confirm volunteer availability or food '
                              'safety.',
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
                                'Estimated road route',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Road distance: '
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
                              const SizedBox(height: 8),
                              const Text(
                                'This is an estimated driving time, not a '
                                'guaranteed arrival time. Traffic, road '
                                'closures, and actual travel conditions '
                                'may differ.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_routeError != null) ...[
                      Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        color: Theme.of(context)
                            .colorScheme
                            .errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_routeError!),
                        ),
                      ),
                    ],
                    OutlinedButton.icon(
                      onPressed: _isLoadingRoute ? null : _loadRoute,
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
                            ? 'Load road route'
                            : 'Reload road route',
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
                            interactionOptions:
                                const InteractionOptions(
                              flags: InteractiveFlag.all,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/'
                                  '{z}/{x}/{y}.png',
                              userAgentPackageName:
                                  'com.example.foodbridge',
                            ),
                            if (route != null)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: route.points,
                                    strokeWidth: 5,
                                    color:
                                        Theme.of(context).primaryColor,
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
          ],
        ),
      ),
    );
  }
}