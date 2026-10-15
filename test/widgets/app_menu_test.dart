import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

void main() {
  testWidgets('AppPopupMenuButton can open its menu through a GlobalKey', (
    tester,
  ) async {
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPopupMenuButton<String>(
            key: key,
            entries: const [AppMenuEntry<String>(value: 'item', label: 'פריט')],
            child: const Text('פתח'),
          ),
        ),
      ),
    );

    final menuFuture = (key.currentState as dynamic).showMenu() as Future<void>;
    await tester.pumpAndSettle();

    expect(find.text('פריט'), findsOneWidget);
    await tester.tap(find.text('פריט'));
    await tester.pumpAndSettle();
    await menuFuture;
  });

  testWidgets('Disabled app menu entries use muted foreground color', (
    tester,
  ) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: AppPopupMenuButton<String>(
                entries: const [
                  AppMenuEntry<String>(
                    value: 'copy',
                    label: 'העתק',
                    icon: FluentIcons.copy_24_regular,
                    enabled: false,
                  ),
                ],
                child: const Text(
                  'פתח',
                  textDirection: TextDirection.rtl,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(find.byIcon(FluentIcons.copy_24_regular));
    expect(
      icon.color,
      theme.colorScheme.onSurface.withValues(alpha: 0.38),
    );
  });
}
