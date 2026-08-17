import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spendsense/core/firebase/firestore_collection.dart';
import 'package:spendsense/features/reminders/domain/entities/reminder.dart';
import 'package:spendsense/features/reminders/domain/repositories/reminder_repository.dart';

class FirestoreReminderRepository implements ReminderRepository {
  FirestoreReminderRepository({required FirebaseFirestore firestore, required String uid})
      : _c = FirestoreCollection<Reminder>(
          firestore: firestore,
          uid: uid,
          name: 'reminders',
          toJson: _toJson,
          fromJson: _fromJson,
        );

  final FirestoreCollection<Reminder> _c;

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
    if (v is String) return DateTime.tryParse(v);
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
