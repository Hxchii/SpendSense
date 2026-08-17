import 'package:spendsense/features/receipts/domain/entities/receipt.dart';

/// Local persistence for saved receipt records — distinct from
/// [ReceiptScanRepository], which performs the (fake-then-real) AI call.
abstract class ReceiptRepository {
  Stream<List<Receipt>> watchAll();
  Future<Receipt> save(Receipt receipt);
  Future<void> delete(String id);

  /// Cheap local heuristic used to flag likely duplicates before a scan is
  /// even sent out: same merchant + total within the last few days.
  Future<Receipt?> findLikelyDuplicate({required String merchant, required int totalMinorUnits, required DateTime date});
}
