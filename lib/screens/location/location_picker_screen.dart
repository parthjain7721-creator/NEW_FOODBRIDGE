import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationPickerScreen extends StatefulWidget {
  final GeoPoint? initialLocation;
  final bool locateOnOpen;

  const LocationPickerScreen({
    super.key,
    this.initialLocation,
    this.locateOnOpen = false,
  });

  @override
  State<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState
    extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();

  LatLng? _selectedPoint;

  bool _isLocating = false;
  bool _confirmedPoint = false;

  String? _locationError;
  double? _accuracyMeters;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialLocation;

    if (initial != null) {
      _selectedPoint = LatLng(
        initial.latitude,
        initial.longitude,
      );
    }

    if (widget.locateOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _useCurrentLocation();
        }
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (_isLocating) {
      return;
    }

    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    try {
      final enabled =
          await Geolocator.isLocationServiceEnabled();

      if (!mounted) {
        return;
      }

      if (!enabled) {
        throw StateError(
          'Device location is switched off. Enable it in settings, '
          'or select the required location manually on the map.',
        );
      }

      var permission = await Geolocator.checkPermission();

      if (!mounted) {
        return;
      }

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (!mounted) {
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        throw StateError(
          'Location permission is blocked. Allow it in app settings, '
          'or select the required location manually on the map.',
        );
      }

      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw StateError(
          'Location permission was not granted. '
          'You can still select a location on the map.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );

      if (!mounted) {
        return;
      }

      final point = LatLng(
        position.latitude,
        position.longitude,
      );

      setState(() {
        _selectedPoint = point;
        _accuracyMeters =
            position.accuracy.isFinite && position.accuracy >= 0
                ? position.accuracy
                : null;
        _confirmedPoint = false;
        _locationError = null;
      });

      _mapController.move(point, 16);
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _locationError =
              'Getting your location took too long. '
              'Try again or select the required location on the map.';
        });
      }
    } on StateError catch (exception) {
      if (mounted) {
        setState(() {
          _locationError = exception.message.toString();
        });
      }
    } catch (exception, stackTrace) {
      debugPrint('Location lookup failed: $exception');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _locationError =
              'Unable to obtain your location. '
              'Try again or select a location on the map.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  Future<void> _openSettings({
    required bool appSettings,
  }) async {
    try {
      final opened = appSettings
          ? await Geolocator.openAppSettings()
          : await Geolocator.openLocationSettings();

      if (!mounted || opened) {
        return;
      }

      _showMessage('Unable to open device settings.');
    } catch (exception) {
      debugPrint(
        'Opening location settings failed: $exception',
      );

      if (mounted) {
        _showMessage('Please open device settings manually.');
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _selectPoint(LatLng point) {
    if (_isLocating) {
      return;
    }

    setState(() {
      _selectedPoint = point;
      _accuracyMeters = null;
      _confirmedPoint = false;
      _locationError = null;
    });
  }

  void _confirmSelection() {
    final point = _selectedPoint;

    if (point == null || !_confirmedPoint || _isLocating) {
      return;
    }

    Navigator.of(context).pop<GeoPoint>(
      GeoPoint(
        point.latitude,
        point.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The default overview does not count as a selected location.
    final initialCenter =
        _selectedPoint ?? const LatLng(20.5937, 78.9629);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose location'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Move and zoom the map, then tap the required '
                    'location. A device location is only a '
                    'starting suggestion.',
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed:
                        _isLocating ? null : _useCurrentLocation,
                    icon: _isLocating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(
                      _isLocating
                          ? 'Finding your location...'
                          : 'Use my current location',
                    ),
                  ),
                  if (_locationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _locationError!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _isLocating
                              ? null
                              : () => _openSettings(
                                    appSettings: false,
                                  ),
                          child: const Text('Location settings'),
                        ),
                        TextButton(
                          onPressed: _isLocating
                              ? null
                              : () => _openSettings(
                                    appSettings: true,
                                  ),
                          child: const Text('App permissions'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom:
                          _selectedPoint == null ? 4.5 : 16,
                      minZoom: 2,
                      maxZoom: 19,
                      onTap: (_, point) => _selectPoint(point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/'
                            '{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.example.foodbridge',
                        maxNativeZoom: 19,
                      ),
                      if (_selectedPoint != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedPoint!,
                              width: 48,
                              height: 48,
                              alignment: Alignment.topCenter,
                              child: const Icon(
                                Icons.location_on,
                                size: 46,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: const Text(
                        '© OpenStreetMap contributors • '
                        'openstreetmap.org/copyright',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _selectedPoint == null
                        ? 'No location selected yet.'
                        : 'Location marker selected. '
                            'Check its position before confirming.',
                  ),
                  if (_accuracyMeters != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Device-reported accuracy: approximately '
                      '${_accuracyMeters!.round()} metres. '
                      'Tap the map to correct the location if needed.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity:
                        ListTileControlAffinity.leading,
                    title: const Text(
                      'This marker is the correct location.',
                    ),
                    value: _confirmedPoint,
                    onChanged:
                        _selectedPoint == null || _isLocating
                            ? null
                            : (value) {
                                setState(() {
                                  _confirmedPoint = value ?? false;
                                });
                              },
                  ),
                  FilledButton.icon(
                    onPressed: _selectedPoint != null &&
                            _confirmedPoint &&
                            !_isLocating
                        ? _confirmSelection
                        : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Confirm location'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}