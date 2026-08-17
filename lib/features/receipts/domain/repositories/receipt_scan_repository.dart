import 'package:spendsense/features/receipts/domain/entities/receipt.dart';

/// Makes the (fake-then-real) AI vision call that turns a receipt photo into
/// structured transaction data. Does not persist anything itself — the
/// caller reviews/edits the result, then saves via [ReceiptRepository].
abstract class ReceiptScanRepository {
  Future<ReceiptScanResult> scan(String imagePath);
}
