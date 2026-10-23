import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';

/// תשובת המארח לפקודה שחלון משני העביר אליו.
typedef HostCommandResponse = ({bool delivered, Object? result});

/// פעולות שרק המארח מבצע: חלון משני שולח אותן ב-[sendToHost], והמארח
/// מטפל בהן ב-`WindowBusHost` ומשדר את מצבן ב-[HostStateBroadcaster].
abstract final class HostRelay {
  /// שולח למארח בקשה מסוג [type]. `delivered` הוא false כשהמארח לא נמצא,
  /// לא ענה בזמן או זרק.
  static Future<HostCommandResponse> sendToHost(
    String type, {
    Map<String, Object?> args = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final owner = WindowBus.instance.ownerPort;
    if (owner == null) return (delivered: false, result: null);
    final response = await WindowBus.instance.requestPortDetailed(
      owner,
      {...args, 'type': type},
      timeout: timeout,
      label: 'owner $type',
    );
    return (delivered: response.failure == null, result: response.result);
  }

  /// תמונת המצב העדכנית של [type] אצל המארח, או null כשלא התקבלה.
  static Future<Map<String, Object?>?> fetchHostSnapshot(String type) async {
    final response = await sendToHost(
      type,
      timeout: const Duration(seconds: 3),
    );
    final result = response.result;
    return result is Map ? Map<String, Object?>.from(result) : null;
  }
}

/// משדר לחלונות האחרים את המצב שהמארח מחזיק. עדכונים צפופים מתלכדים
/// לשידור אחד כל [interval], עם המצב האחרון.
class HostStateBroadcaster {
  HostStateBroadcaster(
    this.type,
    this.snapshot, {
    this.interval = const Duration(milliseconds: 250),
  });

  final String type;
  final Map<String, Object?> Function() snapshot;
  final Duration interval;
  Timer? _pending;

  void changed() {
    if (WindowRole.isSecondary || _pending != null) return;
    if (!WindowBus.instance.hasOtherWindows) return;
    _pending = Timer(interval, () {
      _pending = null;
      try {
        WindowBus.instance.broadcast({'type': type, 'state': snapshot()});
      } catch (error) {
        debugPrint('HostStateBroadcaster $type failed: $error');
      }
    });
  }

  @visibleForTesting
  void flushForTesting() {
    final pending = _pending;
    if (pending == null) return;
    pending.cancel();
    _pending = null;
    WindowBus.instance.broadcast({'type': type, 'state': snapshot()});
  }
}
