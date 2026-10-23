import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_discard_policy.dart';
import 'package:otzaria/plugins/services/plugin_in_book_search_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';

class _Repo extends Fake implements PluginRegistryRepository {
  Completer<bool?>? gate;
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;
  @override
  Future<bool?> getPermission(String pluginId, String permission) async =>
      gate == null ? true : await gate!.future;
}

class _Controller extends Fake implements InAppWebViewController {
  bool paused = false;
  final List<String> whilePaused = [];
  final List<String> delivered = [];
  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    paused = false;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    (paused ? whilePaused : delivered).add(source);
    return null;
  }
}

class _Host implements PluginInstanceHost {
  int releases = 0;
  @override
  bool get canDiscard => true;
  @override
  void releaseWebView() {
    releases++;
  }

  @override
  void restoreWebView() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final d = PluginRuntimeDispatcher.instance;
  const pid = 'lifecycle.regression.plugin';
  PluginInstanceKey key(String id) => (pluginId: pid, instanceId: id);
  late _Repo repo;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await d.prepareForAppRestart();
    d.registerController('__reset', _Controller());
    d.unregisterController('__reset');
    d.resetVisibilityForTesting();
    repo = _Repo();
    d.repositoryForTesting = repo;
    d.invalidatePlugin(pid);
    d.discardLimitsOverride = const PluginDiscardLimits(
      maxLiveSuspended: 0,
      maxSuspendedAge: Duration.zero,
    );
  });
  tearDown(() {
    for (final id in ['a', 'b']) {
      d.unregisterInstanceHost(pid, instanceId: id);
      d.unregisterController(pid, instanceId: id);
      PluginRestoreStateStore.instance.remove(key(id));
    }
    PluginInBookSearchService.instance.removePlugin(pid);
    d.resetVisibilityForTesting();
    d.repositoryForTesting = PluginRegistryRepository();
    d.discardLimitsOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });
  test('legacy tabs keep their state under memory pressure', () async {
    final host = _Host();
    d.registerController(pid, _Controller(), instanceId: 'a');
    d.registerInstanceHost(pid, host, instanceId: 'a');
    d.setVisiblePluginInstances({key('a')});
    await d.onForegroundInstanceReady(pid, instanceId: 'a');
    d.setVisiblePluginInstances({});
    await pumpEventQueue();
    await d.checkDiscard(memoryPressure: true);
    expect(host.releases, 0);
  });
  test(
    'preserve one engine for an active provider during a batch discard',
    () async {
      final a = _Controller(), b = _Controller();
      final ha = _Host(), hb = _Host();
      d.registerController(pid, a, instanceId: 'a');
      d.registerController(pid, b, instanceId: 'b');
      d.registerInstanceHost(pid, ha, instanceId: 'a');
      d.registerInstanceHost(pid, hb, instanceId: 'b');
      d.setVisiblePluginInstances({key('a'), key('b')});
      await d.onForegroundInstanceReady(pid, instanceId: 'a');
      await d.onForegroundInstanceReady(pid, instanceId: 'b');
      d.setVisiblePluginInstances({});
      await pumpEventQueue();
      for (final id in ['a', 'b']) {
        PluginRestoreStateStore.instance.set(key(id), {'screen': id});
      }
      PluginInBookSearchService.instance.register('audit3018', pid);
      await d.checkDiscard(memoryPressure: true);
      expect(
        ha.releases + hb.releases,
        1,
        reason: 'The last provider engine must remain alive',
      );
    },
  );
  test(
    'a state broadcast awaiting permission must queue if its target suspends',
    () async {
      final c = _Controller();
      d.registerController(pid, c, instanceId: 'a');
      d.setVisiblePluginInstances({key('a')});
      await d.onForegroundInstanceReady(pid, instanceId: 'a');
      c.delivered.clear();
      repo.gate = Completer<bool?>();
      final dispatch = d.dispatchEvent('theme.changed', {'mode': 'dark'});
      await pumpEventQueue();
      d.setVisiblePluginInstances({});
      await pumpEventQueue();
      expect(c.paused, isTrue);
      repo.gate!.complete(true);
      await dispatch;
      d.setVisiblePluginInstances({key('a')});
      await pumpEventQueue();
      expect(
        c.delivered.where((s) => s.contains('theme.changed')),
        hasLength(1),
        reason:
            'Theme should arrive after resume rather than being evaluated on a paused WebView',
      );
    },
  );
  test(
    'permission checks do not deliver a queued event to a replacement page',
    () async {
      d.registerController(pid, _Controller(), instanceId: 'a');
      d.setVisiblePluginInstances({key('a')});
      await d.onForegroundInstanceReady(pid, instanceId: 'a');
      d.setVisiblePluginInstances({});
      await pumpEventQueue();
      repo.gate = Completer<bool?>();
      final dispatch = d.dispatchEvent('theme.changed', {'mode': 'dark'});
      await pumpEventQueue();
      d.markInstanceReleased(
        pid,
        instanceId: 'a',
        reason: PluginRestoreReason.crashed,
      );
      final next = _Controller();
      d.registerController(pid, next, instanceId: 'a');
      repo.gate!.complete(true);
      await dispatch;
      expect(next.delivered, isEmpty);
    },
  );
  for (final replacement in ['crash', 'unregister', 'replace']) {
    test(
      'an old RPC cannot finish work in its replacement: $replacement',
      () async {
        final oldController = _Controller();
        final host = _Host();
        d.registerController(pid, oldController, instanceId: 'a');
        d.registerInstanceHost(pid, host, instanceId: 'a');
        d.setVisiblePluginInstances({key('a')});
        await d.onForegroundInstanceReady(pid, instanceId: 'a');
        final endOldWork = d.beginInstanceWork(pid, instanceId: 'a');
        if (replacement == 'crash') {
          d.markInstanceReleased(
            pid,
            instanceId: 'a',
            reason: PluginRestoreReason.crashed,
          );
        } else if (replacement == 'unregister') {
          d.unregisterController(pid, instanceId: 'a');
        }
        d.registerController(pid, _Controller(), instanceId: 'a');
        d.registerInstanceHost(pid, host, instanceId: 'a');
        await d.onForegroundInstanceReady(pid, instanceId: 'a');
        final endNewWork = d.beginInstanceWork(pid, instanceId: 'a');
        PluginRestoreStateStore.instance.set(key('a'), {'screen': 'new'});
        endOldWork();
        d.setVisiblePluginInstances({});
        await pumpEventQueue();
        await d.checkDiscard(memoryPressure: true);
        expect(
          host.releases,
          0,
          reason: 'The replacement page has one unfinished RPC',
        );
        endNewWork();
        await d.checkDiscard(memoryPressure: true);
        expect(host.releases, 1);
      },
    );
  }
}
