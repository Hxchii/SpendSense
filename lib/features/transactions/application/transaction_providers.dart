import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/features/transactions/data/api/api_transaction_repository.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/transactions/domain/repositories/transaction_repository.dart';

/// THE swap point for the transactions domain.
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return ApiTransactionRepository(client: ref.watch(apiClientProvider));
});

final transactionListProvider =
    StreamProvider.autoDispose.family<List<Transaction>, TransactionFilter?>((ref, filter) {
  return ref.watch(transactionRepositoryProvider).watchAll(filter: filter);
});
