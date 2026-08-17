import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spendsense/core/seed/default_categories.dart';

/// Writes the default category set for a brand-new account.
///
/// Idempotent: it checks whether the collection already has documents and
/// does nothing if so, which matters because this runs on every launch and
/// must not resurrect categories the user has deliberately archived.
Future<void> bootstrapAccount({required FirebaseFirestore firestore, required String uid}) async {
  final categories = firestore.collection('users').doc(uid).collection('categories');
  final existing = await categories.limit(1).get();
  if (existing.docs.isNotEmpty) return;

  final batch = firestore.batch();
  for (final c in defaultCategories) {
    batch.set(categories.doc(c.id), {
      'name': c.name,
      'type': c.type.name,
      'iconKey': c.iconKey,
      'colorHex': c.colorHex,
      'isDefault': c.isDefault,
      'archived': c.archived,
    });
  }
  await batch.commit();
}
