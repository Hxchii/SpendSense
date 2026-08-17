import 'package:spendsense/core/utils/money.dart';

enum ReceiptStatus { pending, confirmed, edited }

class ReceiptItem {
  const ReceiptItem({required this.name, required this.qty, required this.price});

  final String name;
  final int qty;
  final Money price;
}

class Receipt {
  const Receipt({
    required this.id,
    required this.merchant,
    required this.date,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
    required this.status,
    this.imagePath,
    this.suggestedCategoryId,
    this.duplicateOfReceiptId,
    this.linkedTransactionId,
  });

  final String id;
  final String? imagePath;
  final String merchant;
  final DateTime date;
  final List<ReceiptItem> items;
  final Money subtotal;
  final Money tax;
  final Money discount;
  final Money total;
  final String? suggestedCategoryId;
  final ReceiptStatus status;
  final String? duplicateOfReceiptId;
  final String? linkedTransactionId;

  Receipt copyWith({ReceiptStatus? status, String? linkedTransactionId, Money? total, String? merchant}) {
    return Receipt(
      id: id,
      merchant: merchant ?? this.merchant,
      date: date,
      items: items,
      subtotal: subtotal,
      tax: tax,
      discount: discount,
      total: total ?? this.total,
      status: status ?? this.status,
      imagePath: imagePath,
      suggestedCategoryId: suggestedCategoryId,
      duplicateOfReceiptId: duplicateOfReceiptId,
      linkedTransactionId: linkedTransactionId ?? this.linkedTransactionId,
    );
  }
}

/// What stopped the model reading the photo cleanly, used to tell the user
/// exactly how to retake it rather than a generic "try again".
enum ReceiptQualityIssue { none, blurry, cropped, glare, tooDark, unreadable }

/// Result of an AI scan call — not yet persisted. The user reviews/edits this
/// before it becomes a saved [Receipt] + [Transaction].
class ReceiptScanResult {
  const ReceiptScanResult({
    required this.merchant,
    required this.date,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
    required this.suggestedCategoryId,
    required this.confidence,
    this.qualityIssue = ReceiptQualityIssue.none,
    this.duplicateOfReceiptId,
  });

  final String merchant;
  final DateTime date;
  final List<ReceiptItem> items;
  final Money subtotal;
  final Money tax;
  final Money discount;
  final Money total;
  final String suggestedCategoryId;
  final double confidence;
  final ReceiptQualityIssue qualityIssue;
  final String? duplicateOfReceiptId;

  /// Below this the extraction isn't trustworthy enough to prefill a
  /// transaction, so the user is asked to retake the photo instead.
  static const minimumConfidence = 0.9;

  bool get isTrustworthy => confidence >= minimumConfidence && qualityIssue == ReceiptQualityIssue.none;
}
