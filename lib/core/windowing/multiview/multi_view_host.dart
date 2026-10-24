import 'package:flutter/material.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';

/// בונה את תוכן החלון הנוסף.
typedef ViewWindowContentBuilder =
    Widget Function(BuildContext context, ViewWindowEntry entry);

/// מעגן את חלונות ה-Dart כתצוגות אחיות של [child], מתחת ל-AppScopeProviders:
/// הם יורשים את ספקי התהליך בלבד, לא את ספקי החלון הראשי.
class MultiViewHost extends StatefulWidget {
  const MultiViewHost({
    super.key,
    this.registry,
    this.contentBuilder = _placeholder,
    required this.child,
  });

  /// ברירת המחדל היא [ViewWindowRegistry.instance].
  final ViewWindowRegistry? registry;
  final ViewWindowContentBuilder contentBuilder;
  final Widget child;

  @override
  State<MultiViewHost> createState() => _MultiViewHostState();

  static Widget _placeholder(BuildContext context, ViewWindowEntry entry) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: Text('חלון ${entry.slot}'))),
        ),
      );
}

class _MultiViewHostState extends State<MultiViewHost> {
  // ⚠️ ל-View יש GlobalKey לפי ה-FlutterView, ובאתחול מחדש באותו פריים הוא
  // מועבר כמו שהוא; מפתח לכל מופע של המארח מכריח בנייה מחדש של העץ שבתוכו.
  final Object _generation = Object();

  @override
  Widget build(BuildContext context) {
    final windows = widget.registry ?? ViewWindowRegistry.instance;
    // ViewAnchor קבוע גם בלי חלונות, כדי שפתיחת הראשון לא תבנה מחדש את child.
    return ListenableBuilder(
      listenable: windows,
      child: widget.child,
      builder: (context, child) {
        final entries = windows.windows;
        return ViewAnchor(
          view: entries.isEmpty
              ? null
              : ViewCollection(
                  views: [
                    for (final entry in entries)
                      View(
                        key: ObjectKey(entry),
                        view: entry.handle.view,
                        child: _FirstFrameReporter(
                          key: ObjectKey(_generation),
                          entry: entry,
                          child: Builder(
                            builder: (context) =>
                                widget.contentBuilder(context, entry),
                          ),
                        ),
                      ),
                  ],
                ),
          child: child!,
        );
      },
    );
  }
}

class _FirstFrameReporter extends StatefulWidget {
  const _FirstFrameReporter({
    super.key,
    required this.entry,
    required this.child,
  });

  final ViewWindowEntry entry;
  final Widget child;

  @override
  State<_FirstFrameReporter> createState() => _FirstFrameReporterState();
}

class _FirstFrameReporterState extends State<_FirstFrameReporter> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.entry.markFirstFrame(),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
