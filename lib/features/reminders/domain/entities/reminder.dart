enum ReminderType { budgetAlert, billReminder, goalReminder, weeklySummary, monthlyReport }

class Reminder {
  const Reminder({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.scheduledFor,
    this.delivered = false,
    this.read = false,
    this.relatedId,
  });

  final String id;
  final ReminderType type;
  final String title;
  final String body;
  final DateTime scheduledFor;
  final bool delivered;
  final bool read;

  // The goal/bill this reminder is about (e.g. a SavingsGoal id for
  // goalReminder) — lets a viewer cross-check the reminder is still current
  // rather than showing stale text (a "50% saved" nudge for a goal that's
  // since been completed) baked in at creation time.
  final String? relatedId;

  Reminder copyWith({bool? delivered, bool? read}) {
    return Reminder(
      id: id,
      type: type,
      title: title,
      body: body,
      scheduledFor: scheduledFor,
      delivered: delivered ?? this.delivered,
      read: read ?? this.read,
      relatedId: relatedId,
    );
  }
}
