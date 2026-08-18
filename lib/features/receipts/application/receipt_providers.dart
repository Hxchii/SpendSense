import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/receipts/data/api/api_receipt_repository.dart';
import 'package:spendsense/features/receipts/data/remote/http_receipt_scan_repository.dart';
import 'package:spendsense/features/receipts/domain/entities/receipt.dart';
import 'package:spendsense/features/receipts/domain/repositories/receipt_repository.dart';
import 'package:spendsense/features/receipts/domain/repositories/receipt_scan_repository.dart';

/// THE swap point for locally-saved receipts.
final receiptRepositoryProvider = Provider<ReceiptRepository>((ref) {
  return ApiReceiptRepository(client: ref.watch(apiClientProvider));
});

/// THE swap point for the AI vision call — now routed through the Laravel
/// API, which holds the Gemini key server-side.
final receiptScanRepositoryProvider = Provider<ReceiptScanRepository>((ref) {
  return HttpReceiptScanRepository(
    client: ref.watch(apiClientProvider),
    // Read through the repositories rather than the autoDispose list
    // providers — those aren't kept alive by the scan screen, so a cold read
    // would hand the model an empty category list.
    loadCategories: () => ref.read(categoryRepositoryProvider).watchAll().first,
    loadReceipts: () => ref.read(receiptRepositoryProvider).watchAll().first,
  );
});

final receiptListProvider = StreamProvider.autoDispose<List<Receipt>>((ref) {
  return ref.watch(receiptRepositoryProvider).watchAll();
});
