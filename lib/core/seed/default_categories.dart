import 'package:spendsense/core/seed/seed_ids.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';

/// The standard category set every new account starts with, so a user can
/// record a transaction (or scan a receipt) immediately without having to
/// build a taxonomy first. These are real app defaults, not demo data —
/// they're written to Firestore once, on first launch, and are editable
/// and archivable from then on.
///
/// Colors are the validated dataviz categorical palette assigned in fixed
/// slot order, so adjacent categories in any chart stay colorblind-safe.
const List<Category> defaultCategories = [
  Category(id: SeedIds.catSalary, name: 'Salary', type: CategoryType.income, iconKey: 'salary', colorHex: '#2a78d6', isDefault: true),
  Category(id: SeedIds.catAllowance, name: 'Allowance', type: CategoryType.income, iconKey: 'allowance', colorHex: '#008300', isDefault: true),
  Category(id: SeedIds.catFood, name: 'Food', type: CategoryType.expense, iconKey: 'food', colorHex: '#2a78d6', isDefault: true),
  Category(id: SeedIds.catTransport, name: 'Transport', type: CategoryType.expense, iconKey: 'transport', colorHex: '#eb6834', isDefault: true),
  Category(id: SeedIds.catBills, name: 'Bills & Utilities', type: CategoryType.expense, iconKey: 'bills', colorHex: '#1baf7a', isDefault: true),
  Category(id: SeedIds.catShopping, name: 'Shopping', type: CategoryType.expense, iconKey: 'shopping', colorHex: '#eda100', isDefault: true),
  Category(id: SeedIds.catEntertainment, name: 'Entertainment', type: CategoryType.expense, iconKey: 'entertainment', colorHex: '#e87ba4', isDefault: true),
  Category(id: SeedIds.catHealth, name: 'Health', type: CategoryType.expense, iconKey: 'health', colorHex: '#008300', isDefault: true),
  Category(id: SeedIds.catEducation, name: 'Education', type: CategoryType.expense, iconKey: 'education', colorHex: '#4a3aa7', isDefault: true),
  Category(id: SeedIds.catOther, name: 'Other', type: CategoryType.expense, iconKey: 'other', colorHex: '#e34948', isDefault: true),
];
