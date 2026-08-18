import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/api/api_collection.dart';
import 'package:spendsense/core/utils/id.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';
import 'package:spendsense/features/categories/domain/repositories/category_repository.dart';

/// Same repository, same contracts, backed by the Laravel API instead of
/// Firestore directly. The serialization below is unchanged from the
/// Firestore version — only the collection wrapper differs.
class ApiCategoryRepository implements CategoryRepository {
  ApiCategoryRepository({required ApiClient client})
      : _c = ApiCollection<Category>(
          client: client,
          name: 'categories',
          toJson: _toJson,
          fromJson: _fromJson,
          idOf: (c) => c.id,
        );

  final ApiCollection<Category> _c;

  static Map<String, dynamic> _toJson(Category c) => {
        'name': c.name,
        'type': c.type.name,
        'iconKey': c.iconKey,
        'colorHex': c.colorHex,
        'isDefault': c.isDefault,
        'archived': c.archived,
      };

  static Category _fromJson(String id, Map<String, dynamic> json) => Category(
        id: id,
        name: json['name'] as String? ?? '',
        type: CategoryType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => CategoryType.expense,
        ),
        iconKey: json['iconKey'] as String? ?? 'other',
        colorHex: json['colorHex'] as String? ?? '#4C6FFF',
        isDefault: json['isDefault'] as bool? ?? false,
        archived: json['archived'] as bool? ?? false,
      );

  @override
  Stream<List<Category>> watchAll({CategoryType? type, bool includeArchived = false}) {
    return _c.watch().map((categories) {
      final visible = categories.where((c) {
        if (!includeArchived && c.archived) return false;
        if (type != null && c.type != type) return false;
        return true;
      }).toList();
      visible.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return visible;
    });
  }

  @override
  Future<Category?> getById(String id) => _c.getById(id);

  @override
  Future<Category> create(CategoryDraft draft) async {
    final category = Category(
      id: newId(),
      name: draft.name,
      type: draft.type,
      iconKey: draft.iconKey,
      colorHex: draft.colorHex,
    );
    await _c.put(category.id, category);
    return category;
  }

  @override
  Future<Category> update(Category category) async {
    await _c.put(category.id, category);
    return category;
  }

  @override
  Future<void> archive(String id) async {
    final existing = await _c.getById(id);
    if (existing == null) return;
    await _c.put(id, existing.copyWith(archived: true));
  }
}
