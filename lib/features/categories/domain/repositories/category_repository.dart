import 'package:spendsense/features/categories/domain/entities/category.dart';

abstract class CategoryRepository {
  Stream<List<Category>> watchAll({CategoryType? type, bool includeArchived = false});
  Future<Category?> getById(String id);
  Future<Category> create(CategoryDraft draft);
  Future<Category> update(Category category);
  Future<void> archive(String id);
}
