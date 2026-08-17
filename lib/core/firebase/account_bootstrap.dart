import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spendsense/core/seed/default_categories.dart';

/// Ensures the account has the default categories.
///
/// Writes only the ones that are genuinely absent, so this stays safe to run
/// on every launch: archiving sets a flag rather than deleting, so an
/// archived category still counts as present and is never resurrected, and
/// renamed or recoloured defaults are left untouched. Accounts created before
/// a new default was introduced pick it up on their next launch.
Future<void> bootstrapAccount({required FirebaseFirestore firestore, required String uid}) async {
  final categories = firestore.collection('users').doc(uid).collection('categories');

  final snapshot = await categories.get();
  // An empty result from the local cache while offline would otherwise look
  // like a brand-new account and re-seed over the user's real categories.
  if (snapshot.metadata.isFromCache && snapshot.docs.isEmpty) return;

  final existingIds = snapshot.docs.map((d) => d.id).toSet();
  final missing = defaultCategories.where((c) => !existingIds.contains(c.id)).toList();
  if (missing.isEmpty) return;

  final batch = firestore.batch();
  for (final c in missing) {
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
