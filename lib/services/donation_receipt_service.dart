import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class DonationReceiptService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> shareAcceptedDonationReceipt({
    required String donationId,
  }) async {
    final String? uid = _auth.currentUser?.uid;

    if (uid == null) {
      throw StateError('Please log in again.');
    }

    if (donationId.isEmpty || donationId.contains('/')) {
      throw StateError('A valid donation ID is required.');
    }

    final snapshot = await _firestore
        .collection('donations')
        .doc(donationId)
        .get(const GetOptions(source: Source.server));

    if (_auth.currentUser?.uid != uid) {
      throw StateError(
        'Your account changed. Please start again.',
      );
    }

    final data = snapshot.data();

    if (!snapshot.exists || data == null) {
      throw StateError('This donation no longer exists.');
    }

    if (data['donorId'] != uid) {
      throw StateError(
        'You can generate a donor receipt only for your own donation.',
      );
    }

    if (data['status'] != 'accepted') {
      throw StateError(
        'A completion receipt is available only after NGO acceptance.',
      );
    }

    final review = _map(data['ngoDeliveryReview']);
    final receivingNgoId = data['claimedByNgoId'];

    if (receivingNgoId is! String ||
        receivingNgoId.isEmpty ||
        review == null ||
        review['decision'] != 'accepted' ||
        review['ngoId'] != receivingNgoId ||
        data['acceptedAt'] is! Timestamp ||
        data['deliveredAt'] is! Timestamp ||
        data['pickedUpAt'] is! Timestamp) {
      throw StateError(
        'The donation is missing required completion records.',
      );
    }

    final Object? quantity = data['quantity'];

    if (quantity is! num ||
        !quantity.isFinite ||
        quantity <= 0) {
      throw StateError(
        'The donation quantity is missing or invalid.',
      );
    }

    final generatedAt = DateTime.now().toUtc();

    final document = pw.Document(
      title: 'FoodBridge Donation Completion Receipt',
      author: 'FoodBridge',
    );

    pw.Widget field(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              _pdfText(value),
              style: const pw.TextStyle(fontSize: 11),
            ),
          ],
        ),
      );
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
        ),
        build: (_) => [
          pw.Text(
            'FoodBridge',
            style: pw.TextStyle(
              fontSize: 26,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green800,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Donation Completion Receipt',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'This document summarizes a donation recorded as '
            'accepted by the receiving NGO in FoodBridge.',
          ),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.SizedBox(height: 12),

          field('Donation reference', donationId),
          field(
            'Food category',
            _text(data['foodCategory'], 'Not recorded'),
          ),
          field(
            'Declared donation quantity',
            '$quantity portions/packets',
          ),
          field('Donor account ID', uid),
          field('Receiving NGO account ID', receivingNgoId),
          field(
            'Assigned volunteer account ID',
            _text(data['assignedVolunteerId'], 'Not recorded'),
          ),

          pw.SizedBox(height: 8),
          pw.Text(
            'Recorded workflow',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),

          field('Posted at', _formatTimestamp(data['postedAt'])),
          field('Claimed at', _formatTimestamp(data['claimedAt'])),
          field(
            'Pickup recorded at',
            _formatTimestamp(data['pickedUpAt']),
          ),
          field(
            'Delivery recorded at',
            _formatTimestamp(data['deliveredAt']),
          ),
          field(
            'NGO acceptance recorded at',
            _formatTimestamp(data['acceptedAt']),
          ),
          field(
            'NGO acceptance notes',
            _text(review['reason'], 'No notes recorded'),
          ),
          field(
            'Receipt generated at',
            generatedAt.toIso8601String(),
          ),

          pw.Divider(),
          pw.SizedBox(height: 12),

          pw.Text(
            'Important limitations',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Quantity is the declared donation quantity. '
            'It is not an independently measured weight, verified '
            'meal count, or confirmed number of beneficiaries.',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'This receipt does not certify food safety, calculate '
            'carbon savings, or constitute a tax receipt. It is '
            'generated on the device and is not digitally signed.',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Workflow timestamps are displayed in UTC. '
            'The receipt-generation time comes from the device.',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );

    final bytes = await document.save();

    if (_auth.currentUser?.uid != uid) {
      throw StateError(
        'Your account changed. The receipt was not shared.',
      );
    }

    final safeId = donationId.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'foodbridge_completion_$safeId.pdf',
    );
  }

  Map<String, dynamic>? _map(dynamic value) {
    return value is Map<String, dynamic> ? value : null;
  }

  String _text(dynamic value, String fallback) {
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : fallback;
  }

  String _formatTimestamp(dynamic value) {
    if (value is! Timestamp) {
      return 'Not recorded';
    }

    return value.toDate().toUtc().toIso8601String();
  }

  // This initial version uses the PDF library's built-in fonts.
  // Preserve basic Latin text and replace unsupported characters.
  String _pdfText(String value) {
    return value
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll(RegExp(r'[^\x20-\x7E\r\n]'), '?');
  }
}