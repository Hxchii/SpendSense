enum CategoryType { income, expense }

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.type,
    required this.iconKey,
    required this.colorHex,
    this.isDefault = false,
    this.archived = false,
  });

  final String id;
  final String name;
  final CategoryType type;
  final String iconKey;
  final String colorHex;
  final bool isDefault;
  final bool archived;

  Category copyWith({String? name, String? iconKey, String? colorHex, bool? archived}) {
    return Category(
      id: id,
      name: name ?? this.name,
      type: type,
      iconKey: iconKey ?? this.iconKey,
      colorHex: colorHex ?? this.colorHex,
      isDefault: isDefault,
      archived: archived ?? this.archived,
    );
  }
}

class CategoryDraft {
  const CategoryDraft({
    required this.name,
    required this.type,
    required this.iconKey,
    required this.colorHex,
  });

  final String name;
  final CategoryType type;
  final String iconKey;
  final String colorHex;
}
