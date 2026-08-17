import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/firebase/firebase_providers.dart';
import 'package:spendsense/features/categories/data/firestore/firestore_category_repository.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';
import 'package:spendsense/features/categories/domain/repositories/category_repository.dart';

/// THE swap point for the categories domain.
final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return FirestoreCategoryRepository(firestore: ref.watch(firestoreProvider), uid: ref.watch(requireUidProvider));
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
