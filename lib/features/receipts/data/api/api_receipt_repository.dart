import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/api/api_collection.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/receipts/domain/entities/receipt.dart';
import 'package:spendsense/features/receipts/domain/repositories/receipt_repository.dart';

/// Same repository, same contracts, backed by the Laravel API instead of
/// Firestore directly. The serialization below is unchanged from the
/// Firestore version — only the collection wrapper differs.
class ApiReceiptRepository implements ReceiptRepository {
  ApiReceiptRepository({required ApiClient client})
      : _c = ApiCollection<Receipt>(
          client: client,
          name: 'receipts',
          toJson: _toJson,
          fromJson: _fromJson,
          idOf: (r) => r.id,
        );

  final ApiCollection<Receipt> _c;

  static Map<String, dynamic> _toJson(Receipt r) => {
        'imagePath': r.imagePath,
        'merchant': r.merchant,
        'date': Timestamp.fromDate(r.date),
        'items': r.items.map(_itemToJson).toList(),
        'subtotalMinor': r.subtotal.minorUnits,
        'taxMinor': r.tax.minorUnits,
        'discountMinor': r.discount.minorUnits,
        'totalMinor': r.total.minorUnits,
        'suggestedCategoryId': r.suggestedCategoryId,
        'status': r.status.name,
        'duplicateOfReceiptId': r.duplicateOfReceiptId,
        'linkedTransactionId': r.linkedTransactionId,
      };

  static Receipt _fromJson(String id, Map<String, dynamic> json) => Receipt(
        id: id,
        imagePath: json['imagePath'] as String?,
        merchant: json['merchant'] as String? ?? '',
        date: _dateFrom(json['date']),
        items: _itemsFrom(json['items']),
        subtotal: Money((json['subtotalMinor'] as num?)?.toInt() ?? 0),
        tax: Money((json['taxMinor'] as num?)?.toInt() ?? 0),
        discount: Money((json['discountMinor'] as num?)?.toInt() ?? 0),
        total: Money((json['totalMinor'] as num?)?.toInt() ?? 0),
        suggestedCategoryId: json['suggestedCategoryId'] as String?,
        status: ReceiptStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => ReceiptStatus.pending,
        ),
        duplicateOfReceiptId: json['duplicateOfReceiptId'] as String?,
        linkedTransactionId: json['linkedTransactionId'] as String?,
      );

  static Map<String, dynamic> _itemToJson(ReceiptItem item) => {
        'name': item.name,
        'qty': item.qty,
        'priceMinor': item.price.minorUnits,
      };

  static List<ReceiptItem> _itemsFrom(Object? v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((m) => ReceiptItem(
              name: m['name'] as String? ?? '',
              qty: (m['qty'] as num?)?.toInt() ?? 1,
              price: Money((m['priceMinor'] as num?)?.toInt() ?? 0),
            ))
        .toList();
  }

  /// Pending local writes surface the value we just wrote (a [DateTime]), and
  /// older/hand-edited documents can hold an ISO string, so accept all three.
  static DateTime _dateFrom(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    // toLocal: the API returns UTC ("...Z"), and DateTime.parse keeps it UTC.
    // Firestore used to hand back local times, so without this every date
    // reads a day early for anything before 08:00 in UTC+8.
    if (v is String) return DateTime.tryParse(v)?.toLocal() ?? DateTime.now();
    return DateTime.now();
  }

  @override
  Stream<List<Receipt>> watchAll() {
    return _c.watch().map((receipts) {
      // Firestore returns documents in document-id order, which for random
      // UUIDs is arbitrary — sort so the list stays stable between rebuilds.
      final sorted = [...receipts]..sort((a, b) => b.date.compareTo(a.date));
      return sorted;
    });
  }

  @override
  Future<Receipt> save(Receipt receipt) async {
    await _c.put(receipt.id, receipt);
    return receipt;
  }

  @override
  Future<void> delete(String id) => _c.delete(id);

  @override
  Future<Receipt?> findLikelyDuplicate({
    required String merchant,
    required int totalMinorUnits,
    required DateTime date,
  }) async {
    final receipts = await _c.getAll();
    return receipts.firstWhereOrNull((r) {
      final sameMerchant = r.merchant.toLowerCase() == merchant.toLowerCase();
      final sameTotal = r.total.minorUnits == totalMinorUnits;
      final withinAWeek = date.difference(r.date).inDays.abs() <= 7;
      return sameMerchant && sameTotal && withinAWeek;
    });
  }
}
