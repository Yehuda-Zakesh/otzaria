import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';

/// למה פקודה לא אושרה.
enum CalendarAlertsFailure {
  /// אין בעלים זמין. דבר לא נכתב.
  noOwner,

  /// הבעלים לא ענה בזמן. ייתכן שהפקודה הוחלה; המצב יתיישר בעדכון הבא.
  timeout,

  /// הבעלים דחה את הפקודה או נכשל בה.
  rejected,
}

/// תשובת הבעלים לפקודה.
@immutable
class CalendarAlertsAck {
  const CalendarAlertsAck._({
    this.failure,
    this.update,
    this.value,
    this.error,
  });

  const CalendarAlertsAck.failed(CalendarAlertsFailure failure, [String? error])
    : this._(failure: failure, error: error);

  final CalendarAlertsFailure? failure;

  /// המצב אחרי הפקודה; null בפקודה שאינה משנה מצב.
  final CalendarAlertsUpdate? update;
  final Object? value;
  final String? error;

  bool get ok => failure == null;

  static CalendarAlertsAck fromReply(Object? reply) {
    if (reply is! Map) {
      return const CalendarAlertsAck.failed(CalendarAlertsFailure.rejected);
    }
    if (reply['ok'] != true) {
      return CalendarAlertsAck.failed(
        CalendarAlertsFailure.rejected,
        reply['error'] as String?,
      );
    }
    return CalendarAlertsAck._(
      update: reply['values'] == null
          ? null
          : CalendarAlertsUpdate.fromJson(reply),
      value: reply['value'],
    );
  }
}

/// הדרך של חלון לשנות את מצב ההתראות: תמיד דרך הבעלים.
abstract class CalendarAlertsClient {
  /// הבעלים עצמו בחלון הראשי ובחלון יחיד, ואפיק החלונות בחלון משני.
  static CalendarAlertsClient forCurrentWindow() =>
      ProcessDuties.current.isProcessOwner
      ? LocalCalendarAlertsClient.instance
      : RemoteCalendarAlertsClient.instance;

  Future<CalendarAlertsAck> send(
    String op, [
    Map<String, Object?> args = const {},
  ]);

  /// עדכוני מצב בסדר עולה בלבד. עדכון ישן נזרק.
  Stream<CalendarAlertsUpdate> get updates;

  Stream<CalendarScheduleStatus> get scheduleStatuses;

  /// האם המצב המקומי עלול להיות ישן ויש לבקש snapshot בפתיחה.
  bool get needsSnapshot;
}

/// מסנן עדכונים לפי epoch ו-revision, ומפרסם רק את החדשים.
mixin _OrderedUpdates {
  String? _epoch;
  int _revision = -1;
  Future<void>? _applying;
  int _applyingDepth = 0;

  final StreamController<CalendarAlertsUpdate> _updates =
      StreamController<CalendarAlertsUpdate>.broadcast(sync: true);

  Stream<CalendarAlertsUpdate> get updates => _updates.stream;

  /// ה-revision האחרון שהוחל בחלון הזה; -1 לפני העדכון הראשון.
  int get appliedRevision => _revision;

  Future<bool> _applyValues(Map<String, Object?> values) async => true;

  /// ההגדרות המקומיות נמחקו: המצב הבא מהבעלים מוחל גם אם ה-revision שלו כבר הוחל.
  void forgetAppliedRevision() {
    _epoch = null;
    _revision = -1;
  }

  /// מחיל ומפרסם את [update] אם הוא חדש. מחזיר false כשנזרק.
  Future<bool> accept(CalendarAlertsUpdate update) {
    if (!update.isNewerThan(_epoch, _revision)) return Future.value(false);
    _epoch = update.epoch;
    _revision = update.revision;
    Future<bool> apply() async {
      // עדכון חדש יותר הגיע בינתיים: הוא שיוחל ויפורסם.
      if (_epoch != update.epoch || _revision != update.revision) return false;
      await _applyValues(update.values);
      _updates.add(update);
      return true;
    }

    final previous = _applying;
    final applied = previous == null ? apply() : previous.then((_) => apply());
    _applyingDepth++;
    _applying = applied.then<void>((_) {}, onError: (Object _) {}).whenComplete(
      () {
        if (--_applyingDepth == 0) _applying = null;
      },
    );
    return applied;
  }
}

/// הבעלים באותו isolate: בלי אפיק ובלי עותק נפרד של ההגדרות.
class LocalCalendarAlertsClient
    with _OrderedUpdates
    implements CalendarAlertsClient {
  LocalCalendarAlertsClient(this.owner) {
    owner.updates.listen(accept);
  }

  static final LocalCalendarAlertsClient instance = LocalCalendarAlertsClient(
    CalendarAlertsOwner.instance,
  );

  final CalendarAlertsOwner owner;

  @override
  bool get needsSnapshot => false;

  @override
  Stream<CalendarScheduleStatus> get scheduleStatuses => owner.scheduleStatuses;

  @override
  Future<CalendarAlertsAck> send(
    String op, [
    Map<String, Object?> args = const {},
  ]) async {
    final ack = CalendarAlertsAck.fromReply(await owner.execute(op, args));
    final update = ack.update;
    if (update != null) await accept(update);
    return ack;
  }
}

/// חלון משני: כל פקודה נשלחת לבעלים, והערכים המאושרים מוחלים על ההגדרות
/// המקומיות דרך [SettingsSync.applyAuthoritativeValues].
class RemoteCalendarAlertsClient
    with _OrderedUpdates
    implements CalendarAlertsClient {
  RemoteCalendarAlertsClient({
    WindowBus? bus,
    Future<bool> Function(Map<String, Object?> values)? applyValues,
    this.timeout = const Duration(seconds: 10),
    this.userTimeout = const Duration(minutes: 5),
  }) : _bus = bus ?? WindowBus.instance,
       _apply = applyValues ?? _applyChangedValues;

  static final RemoteCalendarAlertsClient instance =
      RemoteCalendarAlertsClient();

  final WindowBus _bus;
  final Future<bool> Function(Map<String, Object?> values) _apply;
  final Duration timeout;

  /// לפקודות שעשויות להמתין לדיאלוג הרשאות של המערכת.
  final Duration userTimeout;

  static const Set<String> _waitsForUser = {'ensurePermission', 'sendTest'};

  /// רק מה שהשתנה: כל מפתח שמוחל מרענן את ההגדרות של החלון.
  static Future<bool> _applyChangedValues(Map<String, Object?> values) {
    final changed = {
      for (final entry in values.entries)
        if (Settings.getValue<Object>(entry.key) != entry.value)
          entry.key: entry.value,
    };
    if (changed.isEmpty) return Future.value(true);
    return SettingsSync.instance.applyAuthoritativeValues(changed);
  }

  final StreamController<CalendarScheduleStatus> _statuses =
      StreamController<CalendarScheduleStatus>.broadcast();

  @override
  bool get needsSnapshot => true;

  @override
  Stream<CalendarScheduleStatus> get scheduleStatuses => _statuses.stream;

  @override
  Future<bool> _applyValues(Map<String, Object?> values) => _apply(values);

  @override
  Future<CalendarAlertsAck> send(
    String op, [
    Map<String, Object?> args = const {},
  ]) async {
    final owner = _bus.ownerPort;
    if (owner == null) {
      return const CalendarAlertsAck.failed(CalendarAlertsFailure.noOwner);
    }
    final response = await _bus.requestPortDetailed(
      owner,
      {'type': CalendarAlertsOwner.requestCommand, 'op': op, 'args': args},
      timeout: _waitsForUser.contains(op) ? userTimeout : timeout,
      label: 'calendar alerts $op',
    );
    final ack = switch (response.failure) {
      WindowBusFailure.timeout => const CalendarAlertsAck.failed(
        CalendarAlertsFailure.timeout,
      ),
      WindowBusFailure.error => const CalendarAlertsAck.failed(
        CalendarAlertsFailure.rejected,
      ),
      null => CalendarAlertsAck.fromReply(response.result),
    };
    final update = ack.update;
    if (update != null) await accept(update);
    return ack;
  }

  /// מטפל בשידורי הבעלים. מחזיר null כשההודעה אינה שלנו.
  Future<Object?> handleBusMessage(Map<String, dynamic> message) async {
    switch (message['type']) {
      case CalendarAlertsOwner.requestStateChanged:
        final update = CalendarAlertsUpdate.fromJson(message);
        return update != null && await accept(update);
      case CalendarAlertsOwner.requestScheduleStatus:
        final status = CalendarScheduleStatus.fromJson(message);
        if (status == null) return false;
        _statuses.add(status);
        return true;
    }
    return null;
  }
}
