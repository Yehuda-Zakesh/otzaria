import 'dart:async';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';

class _OwnerRepository extends Fake implements PluginRegistryRepository {
  final owner = Completer<String?>();
  @override
  Future<String?> getNewTabPageOwner() => owner.future;
}

void main() {
  group('PluginNewTabPageRegistry', () {
    const first = 'test.new-tab.first';
    const second = 'test.new-tab.second';
    final registry = PluginNewTabPageRegistry.instance;

    tearDown(() {
      registry.remove(first);
      registry.remove(second);
    });

    test('המתנה לבעלים אינה מעבירה את כפתור פלוס לחלון שקיבל פוקוס', () async {
      final repository = _OwnerRepository();
      final local = PluginNewTabPageRegistry.forTesting(repository)
        ..register(first);
      final a = AppWindowKeys();
      final b = AppWindowKeys();
      final inA = <String>[];
      final inB = <String>[];
      final launcher = PluginPageLauncher.instance;
      launcher.register(a, inA.add);
      launcher.register(b, inB.add);
      addTearDown(() {
        launcher.unregister(a, inA.add);
        launcher.unregister(b, inB.add);
        launcher.forgetWindow(2);
        local.dispose();
        AppWindowKeys.resetForTest();
      });
      final opened = local.open(windowKeys: b, viewId: 2);
      AppWindowKeys.activate(a);
      repository.owner.complete(first);
      await opened;
      expect(inA, isEmpty);
      expect(inB, [first]);
      expect(launcher.hasPendingFor(first), isTrue);
    });

    test('is hidden until a plugin registers', () {
      registry.remove(first);
      registry.remove(second);
      expect(registry.hasActiveRegistration, isFalse);
      expect(registry.activePluginId, isNull);
    });

    test('first registration stays exclusive until explicitly released', () {
      expect(registry.register(first), isTrue);
      expect(registry.activePluginId, first);

      expect(registry.register(second), isFalse);
      expect(registry.activePluginId, first);
      expect(registry.register(first), isTrue);
      expect(registry.activePluginId, first);

      registry.remove(second);
      expect(registry.activePluginId, first);
      registry.remove(first);
      expect(registry.hasActiveRegistration, isFalse);
      expect(registry.activePluginId, isNull);

      // A rejected request is not queued to take over after release.
      expect(registry.hasActiveRegistration, isFalse);
      expect(registry.register(second), isTrue);
      expect(registry.activePluginId, second);
    });

    test('notifies only when the button owner actually changes', () {
      var notifications = 0;
      void listener() => notifications++;
      registry.addListener(listener);
      addTearDown(() => registry.removeListener(listener));

      expect(registry.register(first), isTrue);
      expect(registry.register(first), isTrue);
      expect(registry.register(second), isFalse);
      registry.remove(second);
      registry.remove('test.new-tab.missing');
      expect(notifications, 1);

      registry.remove(first);
      expect(notifications, 2);
      expect(registry.register(second), isTrue);
      expect(notifications, 3);
    });
  });
}
