import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/config/environment.dart';
import 'package:spendsense/core/firebase/firebase_providers.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/receipts/data/firestore/firestore_receipt_repository.dart';
import 'package:spendsense/features/receipts/data/remote/http_receipt_scan_repository.dart';
import 'package:spendsense/features/receipts/domain/entities/receipt.dart';
import 'package:spendsense/features/receipts/domain/repositories/receipt_repository.dart';
import 'package:spendsense/features/receipts/domain/repositories/receipt_scan_repository.dart';

/// THE swap point for locally-saved receipts.
final receiptRepositoryProvider = Provider<ReceiptRepository>((ref) {
  return FirestoreReceiptRepository(firestore: ref.watch(firestoreProvider), uid: ref.watch(requireUidProvider));
});

/// THE swap point for the AI vision call. Later this becomes an HTTP call to
/// the Laravel backend instead (Phase 6) — still a one-line change here.
final receiptScanRepositoryProvider = Provider<ReceiptScanRepository>((ref) {
  return HttpReceiptScanRepository(
    apiKey: Environment.geminiApiKey,
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
