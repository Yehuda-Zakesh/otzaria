import 'dart:isolate';
import 'dart:ui';

import 'package:otzaria/core/windowing/window_bus.dart';

/// המארח המדומה: נרשם בכינוי הבעלים ישירות מול [IsolateNameServer], כי
/// [WindowBus] הוא סינגלטון פר-isolate. מתעד בקשות ועונה לפי [respond].
class FakeHostWindow {
  FakeHostWindow({required this.namespace, this.respond});

  final String namespace;

  /// התשובה לבקשה; ברירת המחדל: true.
  Object? Function(Map<String, dynamic> request)? respond;

  final requests = <Map<String, dynamic>>[];
  late final ReceivePort _port;
  String? _previousNamespace;

  void register() {
    _previousNamespace = WindowBus.namespace;
    WindowBus.namespace = namespace;
    _port = ReceivePort();
    IsolateNameServer.registerPortWithName(_port.sendPort, '$namespace.owner');
    _port.listen((message) {
      final map = message as Map;
      final reply = map['reply'] as SendPort?;
      final body = Map<String, dynamic>.from(map['body'] as Map);
      requests.add(body);
      reply?.send({'ok': true, 'result': (respond ?? (_) => true)(body)});
    });
  }

  List<Map<String, dynamic>> ofType(String type) => [
    for (final request in requests)
      if (request['type'] == type) request,
  ];

  void dispose() {
    IsolateNameServer.removePortNameMapping('$namespace.owner');
    _port.close();
    WindowBus.namespace = _previousNamespace ?? 'otzaria.window';
  }
}
