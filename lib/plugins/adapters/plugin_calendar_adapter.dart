import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';

/// ממיר רשומות `calendar.event` של תוספים לאירועי לוח השנה.
/// תצוגת חלון מסוננת לפי scope; תזמון ההתראות כולל את כל החלונות.
class PluginCalendarAdapter {
  const PluginCalendarAdapter({this.recordsLoader});

  /// מקור הרשומות; ברירת המחדל היא מסד התוספים.
  final Future<List<Map<String, dynamic>>> Function(String type)? recordsLoader;

  /// מאחד רשומות תוספים עם [existingEvents], לפי סביבת העבודה והספר הנוכחיים.
  Future<List<CustomEvent>> loadAndMergePluginEvents(
    List<CustomEvent> existingEvents, {
    String? currentWorkspaceId,
    String? currentBookId,
    String? currentBookUid,
  }) async {
    final pluginEvents = await _load(
      (scope) => _isScopeVisible(
        scope: scope,
        currentWorkspaceId: currentWorkspaceId,
        currentBookId: currentBookId,
        currentBookUid: currentBookUid,
      ),
    );
    return [...existingEvents, ...?pluginEvents];
  }

  /// כל אירועי התוספים, בלי תלות ב-scope: ההתראות אינן תלויות בחלון.
  /// כשל קריאה חייב להתפשט, אחרת התזמון יפרש אותו כמחיקה ויבטל התראות.
  Future<List<CustomEvent>> loadAllPluginEvents() async {
    final events = await _load((_) => true);
    if (events == null) {
      throw StateError('Failed to load plugin calendar events');
    }
    return events;
  }

  /// null = הטעינה נכשלה.
  Future<List<CustomEvent>?> _load(bool Function(String scope) visible) async {
    try {
      final records =
          await (recordsLoader ??
              PluginSystemDatabase.instance.getPublishedRecordsFull)(
            'calendar.event',
          );

      final pluginEvents = <CustomEvent>[];
      for (final record in records) {
        try {
          final pluginId = record['plugin_id'] as String;
          final key = record['key'] as String;
          final scope = record['scope'] as String;
          final rawPayload = jsonDecode(record['payload_json'] as String);

          if (rawPayload is! Map<String, dynamic>) continue;
          if (!visible(scope)) continue;

          final event = _fromPluginPayload(pluginId, key, rawPayload);
          if (event != null) pluginEvents.add(event);
        } catch (e) {
          debugPrint('PluginCalendarAdapter: failed to parse record: $e');
        }
      }
      return pluginEvents;
    } catch (e) {
      debugPrint('PluginCalendarAdapter: failed to load events: $e');
      return null;
    }
  }

  /// קובע האם record מסוים צריך להיות גלוי לפי ה-scope שלו.
  bool _isScopeVisible({
    required String scope,
    String? currentWorkspaceId,
    String? currentBookId,
    String? currentBookUid,
  }) {
    if (scope == 'global') return true;

    if (scope.startsWith('workspace:')) {
      final workspaceId = scope.substring('workspace:'.length);
      return currentWorkspaceId != null && currentWorkspaceId == workspaceId;
    }

    if (scope.startsWith('book:')) {
      // מזוהה גם scope חדש (`book:<bookUid>`) וגם ישן (`book:<כותרת>`).
      final bookId = scope.substring('book:'.length);
      return (currentBookId != null && currentBookId == bookId) ||
          (currentBookUid != null && currentBookUid == bookId);
    }

    // scope לא מוכר — בטח לא להציג
    return false;
  }

  /// ממיר פרטי אירוע מהתוסף לאירוע פנימי.
  CustomEvent? _fromPluginPayload(
    String pluginId,
    String key,
    Map<String, dynamic> payload,
  ) {
    final title = payload['title'] as String?;
    final startsAtRaw = payload['startsAt'] as String?;
    if (title == null || startsAtRaw == null) return null;

    final startsAt = DateTime.tryParse(startsAtRaw);
    if (startsAt == null) return null;

    // source + importance → description
    final source = payload['source'] as String? ?? '';
    final importance = payload['importance'] as String?;
    final description = (importance != null && importance.isNotEmpty)
        ? '$source ($importance)'
        : source;

    // המרה לתאריך עברי
    final jwDate = JewishDate.fromDateTime(startsAt);

    return CustomEvent(
      id: '$pluginId:$key',
      title: title,
      description: description,
      createdAt: DateTime.now(),
      baseGregorianDate: DateTime(startsAt.year, startsAt.month, startsAt.day),
      baseJewishYear: jwDate.getJewishYear(),
      baseJewishMonth: jwDate.getJewishMonth(),
      baseJewishDay: jwDate.getJewishDayOfMonth(),
      recurrenceType: RecurrenceType.none,
    );
  }
}
