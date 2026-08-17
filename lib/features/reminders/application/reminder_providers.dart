import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/firebase/firebase_providers.dart';
import 'package:spendsense/features/reminders/data/firestore/firestore_reminder_repository.dart';
import 'package:spendsense/features/reminders/domain/entities/reminder.dart';
import 'package:spendsense/features/reminders/domain/repositories/reminder_repository.dart';

/// THE swap point for the reminders domain.
final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  return FirestoreReminderRepository(firestore: ref.watch(firestoreProvider), uid: ref.watch(requireUidProvider));
});

final reminderListProvider = StreamProvider.autoDispose<List<Reminder>>((ref) {
  return ref.watch(reminderRepositoryProvider).watchAll();
});
