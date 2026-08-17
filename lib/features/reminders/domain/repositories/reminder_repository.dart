import 'package:spendsense/features/reminders/domain/entities/reminder.dart';

abstract class ReminderRepository {
  Stream<List<Reminder>> watchAll();
  Future<Reminder> create(Reminder reminder);
  Future<void> markRead(String id);
}
