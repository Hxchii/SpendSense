import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/features/categories/data/api/api_category_repository.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';
import 'package:spendsense/features/categories/domain/repositories/category_repository.dart';

/// THE swap point for the categories domain.
final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return ApiCategoryRepository(client: ref.watch(apiClientProvider));
});

final categoryListProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchAll();
});

final incomeCategoryListProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchAll(type: CategoryType.income);
});

final expenseCategoryListProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchAll(type: CategoryType.expense);
});
