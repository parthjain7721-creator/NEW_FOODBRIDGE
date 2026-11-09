import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class FoodBridgeRoute {
  final List<LatLng> points;
  final double distanceMetres;
  final double durationSeconds;

  const FoodBridgeRoute({
    required this.points,
    required this.distanceMetres,
    required this.durationSeconds,
  });

  double get distanceKilometres => distanceMetres / 1000;

  int get estimatedMinutes => (durationSeconds / 60).ceil();
}

class RouteService {
  static const String _apiKey = String.fromEnvironment(
    'ORS_API_KEY',
  );

  // Use the full Directions GeoJSON endpoint shown in your
  // OpenRouteService API documentation/dashboard.
  static const String _directionsUrl = String.fromEnvironment(
    'ORS_DIRECTIONS_URL',
  );

  Future<FoodBridgeRoute> getDrivingRoute({
    required GeoPoint pickup,
    required GeoPoint destination,
    GeoPoint? startingPoint,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw StateError(
        'OpenRouteService is not configured. '
        'Start the app with ORS_API_KEY.',
      );
    }

    final uri = Uri.tryParse(_directionsUrl);

    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      throw StateError(
        'A valid HTTPS ORS_DIRECTIONS_URL is required.',
      );
    }

    final coordinates = <List<double>>[
      if (startingPoint != null)
        [
          startingPoint.longitude,
          startingPoint.latitude,
        ],
      [
        pickup.longitude,
        pickup.latitude,
      ],
      [
        destination.longitude,
        destination.latitude,
      ],
    ];

    final client = http.Client();

    try {
      final response = await client
          .post(
            uri,
            headers: {
              'Authorization': _apiKey,
              'Content-Type': 'application/json',
              'Accept': 'application/geo+json, application/json',
            },
            body: jsonEncode({
              'coordinates': coordinates,
              'instructions': false,
              'elevation': false,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        switch (response.statusCode) {
          case 400:
            throw StateError(
              'The routing service could not process these locations. '
              'Check that the selected points are near accessible roads.',
            );

          case 401:
          case 403:
            throw StateError(
              'OpenRouteService rejected the request. '
              'Check your API key and account permissions.',
            );

          case 404:
            throw StateError(
              'The Directions endpoint or a suitable route was not found. '
              'Check ORS_DIRECTIONS_URL and the selected locations.',
            );

          case 429:
            throw StateError(
              'The routing request limit has been reached. '
              'Please try again later.',
            );

          default:
            throw StateError(
              'The routing service is unavailable. '
              '(HTTP ${response.statusCode})',
            );
        }
      }

      final Object? decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid route response.');
      }

      final Object? features = decoded['features'];

      if (features is! List || features.isEmpty) {
        throw StateError(
          'No road route was returned for these locations.',
        );
      }

      final Object? firstFeature = features.first;

      if (firstFeature is! Map<String, dynamic>) {
        throw const FormatException('Invalid route feature.');
      }

      final Object? geometry = firstFeature['geometry'];
      final Object? properties = firstFeature['properties'];

      if (geometry is! Map<String, dynamic> ||
          geometry['type'] != 'LineString' ||
          properties is! Map<String, dynamic>) {
        throw const FormatException('Invalid route geometry.');
      }

      final Object? rawPoints = geometry['coordinates'];
      final Object? summary = properties['summary'];

      if (rawPoints is! List ||
          summary is! Map<String, dynamic>) {
        throw const FormatException('Missing route details.');
      }

      final Object? distance = summary['distance'];
      final Object? duration = summary['duration'];

      if (distance is! num ||
          !distance.isFinite ||
          distance < 0 ||
          duration is! num ||
          !duration.isFinite ||
          duration < 0) {
        throw const FormatException('Invalid route summary.');
      }

      final points = <LatLng>[];

      for (final Object? rawPoint in rawPoints) {
        if (rawPoint is! List || rawPoint.length < 2) {
          throw const FormatException('Invalid route coordinate.');
        }

        final Object? longitude = rawPoint[0];
        final Object? latitude = rawPoint[1];

        if (longitude is! num ||
            latitude is! num ||
            !longitude.isFinite ||
            !latitude.isFinite ||
            longitude < -180 ||
            longitude > 180 ||
            latitude < -90 ||
            latitude > 90) {
          throw const FormatException('Invalid route coordinate.');
        }

        points.add(
          LatLng(
            latitude.toDouble(),
            longitude.toDouble(),
          ),
        );
      }

      if (points.length < 2) {
        throw StateError(
          'The routing service did not return a usable road route.',
        );
      }

      return FoodBridgeRoute(
        points: List<LatLng>.unmodifiable(points),
        distanceMetres: distance.toDouble(),
        durationSeconds: duration.toDouble(),
      );
    } on TimeoutException {
      throw StateError(
        'The route request timed out. Please try again.',
      );
    } on http.ClientException {
      throw StateError(
        'Unable to connect to the routing service. '
        'Check your internet connection.',
      );
    } on FormatException {
      throw StateError(
        'The routing service returned an unexpected response.',
      );
    } finally {
      client.close();
    }
  }
}