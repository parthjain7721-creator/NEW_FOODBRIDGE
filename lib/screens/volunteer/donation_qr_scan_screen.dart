import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class DonationQrScanScreen extends StatefulWidget {
  final String donationId;

  const DonationQrScanScreen({
    super.key,
    required this.donationId,
  });

  @override
  State<DonationQrScanScreen> createState() =>
      _DonationQrScanScreenState();
}

class _DonationQrScanScreenState
    extends State<DonationQrScanScreen> {
  bool _isChecking = false;
  bool _completed = false;

  DateTime? _lastAttemptAt;
  String _statusMessage =
      'Point the camera at the donor’s Donation Passport QR code.';

  String? _extractDonationId(String rawValue) {
    final String value = rawValue.trim();

    if (value.isEmpty) {
      return null;
    }

    // Optional structured format for future Donation Passports.
    try {
      final Object? decoded = jsonDecode(value);

      if (decoded is Map<String, dynamic> &&
          decoded['type'] == 'foodbridge_donation_passport') {
        final Object? id = decoded['donationId'];

        if (id is String && id.trim().isNotEmpty) {
          return id.trim();
        }
      }
    } on FormatException {
      // Existing passports contain readable multiline text.
    }

    // Matches the readable QR format previously used by FoodBridge:
    //
    // FoodBridge Donation Passport
    // Donation ID: <id>
    // ...
    final List<String> lines = value
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty ||
        lines.first != 'FoodBridge Donation Passport') {
      return null;
    }

    final List<String> idLines = lines.where((line) {
      return line.startsWith('Donation ID:');
    }).toList();

    if (idLines.length != 1) {
      return null;
    }

    final String id =
        idLines.single.substring('Donation ID:'.length).trim();

    return id.isEmpty ? null : id;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isChecking || _completed) {
      return;
    }

    final DateTime now = DateTime.now();

    if (_lastAttemptAt != null &&
        now.difference(_lastAttemptAt!) < const Duration(seconds: 2)) {
      return;
    }

    String? rawValue;

    for (final barcode in capture.barcodes) {
      final String? value = barcode.rawValue;

      if (value != null && value.trim().isNotEmpty) {
        rawValue = value;
        break;
      }
    }

    if (rawValue == null) {
      return;
    }

    _lastAttemptAt = now;
    _verifyCode(rawValue);
  }

  Future<void> _verifyCode(String rawValue) async {
    if (_isChecking || _completed) {
      return;
    }

    final String? scannedId = _extractDonationId(rawValue);

    if (scannedId == null) {
      setState(() {
        _statusMessage =
            'This is not a recognized FoodBridge Donation Passport.';
      });
      return;
    }

    if (scannedId != widget.donationId) {
      setState(() {
        _statusMessage =
            'Wrong donation. Scan the passport for your assigned task.';
      });
      return;
    }

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        _statusMessage = 'Your session has ended. Please log in again.';
      });
      return;
    }

    setState(() {
      _isChecking = true;
      _statusMessage = 'Checking the current donation record...';
    });

    try {
      // Require a server response, not an offline cached record.
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('donations')
              .doc(widget.donationId)
              .get(const GetOptions(source: Source.server));

      final Map<String, dynamic>? data = snapshot.data();

      if (!snapshot.exists || data == null) {
        throw StateError('This donation no longer exists.');
      }

      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        throw StateError('Your login session changed. Please try again.');
      }

      if (data['assignedVolunteerId'] != user.uid) {
        throw StateError('This donation is not assigned to you.');
      }

      if (data['status'] != 'volunteer_assigned' ||
          data['volunteerAssignmentStatus'] != 'assigned') {
        throw StateError(
          'This task is not currently awaiting pickup.',
        );
      }

      if (data['ngoPickupConfirmed'] != true ||
          data['donorPickupConfirmed'] != true ||
          data['ngoCapacityConfirmed'] != true ||
          data['ngoDetailsReviewed'] != true) {
        throw StateError(
          'The required donor and NGO confirmations are incomplete.',
        );
      }

      if (data['eligibilityStatus'] != 'eligible' &&
          data['eligibilityStatus'] != 'urgent') {
        throw StateError(
          'This donation is not eligible for ordinary pickup.',
        );
      }

      final Object? rawDeadline = data['pickupDeadline'];

      if (rawDeadline is! Timestamp ||
          !rawDeadline.toDate().isAfter(DateTime.now())) {
        throw StateError(
          'The pickup window has closed or its deadline is missing.',
        );
      }

      if (!mounted) {
        return;
      }

      _completed = true;

      Navigator.of(context).pop<bool>(true);
    } on FirebaseException catch (error) {
      debugPrint(
        'QR verification failed: ${error.code} - ${error.message}',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage =
            'Unable to verify the current donation. '
            'Check your connection and try again. (${error.code})';
      });
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = error.message.toString();
      });
    } catch (error) {
      debugPrint('Unexpected QR verification error: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = 'Unable to verify this QR code. Please try again.';
      });
    } finally {
      if (mounted && !_completed) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Donation Passport'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    onDetect: _onDetect,
                    errorBuilder: (context, error) {
                      return Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Unable to open the camera.\n\n'
                            'Allow camera access in your device settings '
                            'and reopen this screen.\n\n$error',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    },
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  if (_isChecking)
                    const ColoredBox(
                      color: Color(0x66000000),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'QR matching identifies the donation batch. '
                    'Packaging inspection and pickup evidence '
                    'are still required.',
                    textAlign: TextAlign.center,
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