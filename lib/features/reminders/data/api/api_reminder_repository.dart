import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/api/api_collection.dart';
import 'package:spendsense/features/reminders/domain/entities/reminder.dart';
import 'package:spendsense/features/reminders/domain/repositories/reminder_repository.dart';

/// Same repository, same contracts, backed by the Laravel API instead of
/// Firestore directly. The serialization below is unchanged from the
/// Firestore version — only the collection wrapper differs.
class ApiReminderRepository implements ReminderRepository {
  ApiReminderRepository({required ApiClient client})
      : _c = ApiCollection<Reminder>(
          client: client,
          name: 'reminders',
          toJson: _toJson,
          fromJson: _fromJson,
          idOf: (r) => r.id,
        );

  final ApiCollection<Reminder> _c;

  static Map<String, dynamic> _toJson(Reminder r) => {
        'type': r.type.name,
        'title': r.title,
        'body': r.body,
        'scheduledFor': Timestamp.fromDate(r.scheduledFor),
        'delivered': r.delivered,
        'read': r.read,
        'relatedId': r.relatedId,
      };

  static Reminder _fromJson(String id, Map<String, dynamic> json) => Reminder(
        id: id,
        type: ReminderType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ReminderType.billReminder,
        ),
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        scheduledFor: _dateFrom(json['scheduledFor']) ?? DateTime.now(),
        delivered: json['delivered'] as bool? ?? false,
        read: json['read'] as bool? ?? false,
        relatedId: json['relatedId'] as String?,
      );

  /// Firestore hands back a `Timestamp`, but a locally-cached write can still
  /// surface the raw `DateTime`, and older documents may hold an ISO string.
  static DateTime? _dateFrom(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    // toLocal: the API returns UTC ("...Z"), and DateTime.parse keeps it UTC.
    // Firestore used to hand back local times, so without this every date
    // reads a day early for anything before 08:00 in UTC+8.
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  @override
  Stream<List<Reminder>> watchAll() {
    return _c.watch().map((reminders) {
      // Documents arrive in UUID order, so impose the newest-first order the
      // in-memory list happened to hold.
      final sorted = [...reminders]..sort((a, b) => b.scheduledFor.compareTo(a.scheduledFor));
      return sorted;
    });
  }

  @override
  Future<Reminder> create(Reminder reminder) async {
    await _c.put(reminder.id, reminder);
    return reminder;
  }

  @override
  Future<void> markRead(String id) async {
    final existing = await _c.getById(id);
    if (existing == null) return;
    await _c.put(id, existing.copyWith(read: true));
  }
}
