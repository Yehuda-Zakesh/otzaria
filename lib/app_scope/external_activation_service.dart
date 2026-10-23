import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/external_activation_channel.dart';
import 'package:otzaria/core/external_activation_queue.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/last_active_window.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/window_bus.dart';

/// פותח קישור בחלון הזה. מחזיר `true` אם הקישור טופל.
typedef ExternalUriHandler = Future<bool> Function(String uriString);

/// חלון שמקבל קישורים, ואם הוא מוצג כרגע.
typedef _AttachedWindow = ({
  ExternalUriHandler handler,
  Future<bool> Function() isVisible,
});

/// הפעלות חיצוניות (otzaria:// וקבצים ממופע נוסף) ברמת התהליך: ערוץ, תור וניתוב.
/// החלון נרשם ב-[attachWindow] ופותח את הקישור בפועל.
class ExternalActivationService {
  ExternalActivationService({
    ExternalActivationQueue? queue,
    ExternalActivationChannel? channel,
    bool Function()? canOpenWindows,
    Future<int?> Function()? lastActiveSlot,
    int? Function()? ownSlot,
    Future<Object?> Function(int slot, Map<String, dynamic> body)? forward,
    Stream<FileSystemEvent> Function(Directory dir)? watchDirectory,
    bool Function()? multiView,
    AppWindowId Function()? lastActiveWindow,
  }) : _queue = queue ?? const ExternalActivationQueue(),
       _channel = channel ?? ExternalActivationChannel(),
       _canOpenWindows =
           canOpenWindows ?? (() => MultiWindowService.canOpenWindows),
       _lastActiveSlot =
           lastActiveSlot ??
           (() => const MultiWindowService().lastActiveSlot()),
       _ownSlot = ownSlot ?? (() => WindowBus.instance.slot),
       _forward = forward ?? _forwardOverBus,
       _watchDirectory = watchDirectory ?? ((dir) => dir.watch()),
       _multiView = multiView ?? (() => MultiViewMode.enabled),
       _lastActiveWindow = lastActiveWindow ?? (() => LastActiveWindow.id);

  final ExternalActivationQueue _queue;
  final ExternalActivationChannel _channel;
  final bool Function() _canOpenWindows;
  final Future<int?> Function() _lastActiveSlot;
  final int? Function() _ownSlot;
  final Future<Object?> Function(int slot, Map<String, dynamic> body) _forward;
  final Stream<FileSystemEvent> Function(Directory dir) _watchDirectory;
  final bool Function() _multiView;
  final AppWindowId Function() _lastActiveWindow;

  late final CoalescingDrainRunner _drainRunner = CoalescingDrainRunner(
    _drainPending,
  );
  StreamSubscription<FileSystemEvent>? _watchSub;
  StreamSubscription<String>? _channelSub;
  ExternalUriHandler? _window;
  Future<bool> Function() _windowVisible = _alwaysVisible;

  /// חלונות Dart באותו isolate, לפי סדר הרישום.
  final Map<AppWindowId, _AttachedWindow> _views = {};

  static Future<bool> _alwaysVisible() async => true;

  static Future<Object?> _forwardOverBus(
    int slot,
    Map<String, dynamic> body,
  ) => WindowBus.instance.request(
    slot,
    body,
    timeout: const Duration(seconds: 5),
  );

  /// רושם את החלון של ה-isolate הזה כיעד המקומי.
  void attachWindow(
    ExternalUriHandler handler, {
    Future<bool> Function()? isVisible,
  }) {
    _window = handler;
    _windowVisible = isVisible ?? _alwaysVisible;
  }

  /// מסיר את [handler] אם הוא הרשום; קישורים שיגיעו אחר כך לא יטופלו כאן.
  void detachWindow(ExternalUriHandler handler) {
    if (_window == handler) _window = null;
  }

  /// רושם חלון Dart ([MultiViewMode]) כיעד אפשרי לקישורים שנוקזו.
  void attachViewWindow(
    AppWindowId id,
    ExternalUriHandler handler, {
    required Future<bool> Function() isVisible,
  }) => _views[id] = (handler: handler, isVisible: isVisible);

  void detachViewWindow(AppWindowId id, ExternalUriHandler handler) {
    if (_views[id]?.handler == handler) _views.remove(id);
  }

  /// מפעיל את הערוץ, מטפל בקישורים שהמתינו בפלטפורמה, מנטר את התור ומנקז.
  Future<void> start() async {
    await _channel.initialize();
    await _channelSub?.cancel();
    _channelSub = _channel.uriStrings.listen((uriString) {
      unawaited(_deliverHere(uriString));
    });

    final pendingPlatformUris = await _channel.takePendingUriStrings();
    for (final uriString in pendingPlatformUris) {
      await _deliverHere(uriString);
    }

    final queuePath = await _queue.resolveQueueFilePath();
    final queueFile = File(queuePath);
    await queueFile.parent.create(recursive: true);

    await _watchSub?.cancel();
    _watchSub = _watchDirectory(queueFile.parent).listen(
      (event) {
        final normalizedPath = event.path.replaceAll('\\', '/');
        final normalizedQueuePath = queuePath.replaceAll('\\', '/');
        if (normalizedPath != normalizedQueuePath) {
          return;
        }

        unawaited(processPending());
      },
      onError: (error, stackTrace) {
        debugPrint('External activation watch failed: $error\n$stackTrace');
      },
    );

    await processPending();
  }

  /// מנקז את התור; קריאה באמצע ניקוז גורמת לניקוז נוסף מיד אחריו.
  Future<void> processPending() => _drainRunner.run();

  void dispose() {
    _watchSub?.cancel();
    _channelSub?.cancel();
    _channel.dispose();
    _window = null;
    _views.clear();
  }

  Future<void> _drainPending() async {
    if (_window == null) return;
    try {
      final pendingUris = await _queue.drainUriStrings();
      for (final uriString in pendingUris) {
        await _routeDrainedUri(uriString);
      }
    } catch (e, stackTrace) {
      debugPrint('External activation polling failed: $e\n$stackTrace');
    }
  }

  /// מפנה קישור שנוקז אל החלון הגלוי שהיה פעיל אחרון, או מטפל בו כאן.
  ///
  /// המארח הוא המנקז היחיד, ולכן בלי ההפניה הזו הקישור היה נפתח תמיד בו —
  /// גם כשהמשתמש עובד בחלון אחר.
  Future<void> _routeDrainedUri(String uriString) async {
    final uri = Uri.tryParse(uriString);
    final action = uri == null ? null : ExternalUriRouter.parseUri(uri);
    // "חלון חדש" לא ביקש חלון קיים — אין למי להפנות.
    if (action is OpenNewWindowAction || !_canOpenWindows()) {
      await _deliverHere(uriString);
      return;
    }
    // החלונות באותו isolate: ה-runner מכיר רק את החלון הראשי.
    if (_multiView()) {
      final view = await _viewWindowTarget();
      if (view != null && await view(uriString)) return;
      await _deliverHere(uriString);
      return;
    }

    final slot = await _lastActiveSlot();
    if (_window == null) return;
    // null = אין חלון גלוי; אז המארח מוצג בכוונה — משהו חייב להופיע.
    if (slot == null || slot == _ownSlot()) {
      await _deliverHere(uriString);
      return;
    }

    final handled = await _forward(slot, {
      'type': MultiWindowService.requestOpenUri,
      'uri': uriString,
    });
    if (handled == true || _window == null) return;
    // היעד לא ענה או סירב — עדיף שהקישור ייפתח כאן מאשר שייעלם.
    await _deliverHere(uriString);
  }

  /// כמו `lastActiveSlot` של ה-runner: החלון הגלוי שהיה פעיל אחרון. ראשי
  /// מוסתר אינו מוחזר כל עוד חלון אחר גלוי; `null` — החלון הראשי.
  Future<ExternalUriHandler?> _viewWindowTarget() async {
    if (_views.isEmpty) return null;
    final last = _views[_lastActiveWindow()];
    if (last != null && await last.isVisible()) return last.handler;
    if (await _windowVisible()) return null;
    for (final view in _views.values.toList().reversed) {
      if (await view.isVisible()) return view.handler;
    }
    // אין חלון גלוי: הראשי מציג את עצמו, כמו ב-runner.
    return null;
  }

  Future<bool> _deliverHere(String uriString) {
    final window = _window;
    return window == null ? Future.value(false) : window(uriString);
  }
}
