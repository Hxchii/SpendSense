import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/features/reminders/data/api/api_reminder_repository.dart';
import 'package:spendsense/features/reminders/domain/entities/reminder.dart';
import 'package:spendsense/features/reminders/domain/repositories/reminder_repository.dart';

/// THE swap point for the reminders domain.
final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  return ApiReminderRepository(client: ref.watch(apiClientProvider));
});

final reminderListProvider = StreamProvider.autoDispose<List<Reminder>>((ref) {
  return ref.watch(reminderRepositoryProvider).watchAll();
});
