import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/bundled_plugin_seed_service.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';

class _FakeRepo implements PluginRegistryRepository {
  int devPluginQueries = 0;

  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async {
    devPluginQueries++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _CountingSeedService implements BundledPluginSeedService {
  int seeds = 0;

  @override
  Future<bool> seedPending() async {
    seeds++;
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool oldSecondary;
  late _FakeRepo repo;
  late _CountingSeedService seed;

  setUp(() {
    oldSecondary = WindowRole.isSecondary;
    PluginSafeMode.active.value = false;
    repo = _FakeRepo();
    seed = _CountingSeedService();
  });

  tearDown(() {
    WindowRole.isSecondary = oldSecondary;
    ProcessDuties.debugOverride = null;
    PluginSafeMode.resetForTesting();
  });

  Future<void> run(PluginSystemBloc bloc, PluginSystemEvent event) async {
    bloc.add(event);
    await pumpEventQueue(times: 50);
    await bloc.close();
  }

  PluginSystemBloc build({ProcessDuties? duties}) => PluginSystemBloc(
    repository: repo,
    bundledSeedService: seed,
    processDuties: duties,
  );

  group('SeedBundledPlugins שואל את ProcessDuties', () {
    test('לא-בעלים אינו זורע, גם כש-WindowRole אומר ראשי', () async {
      WindowRole.isSecondary = false;
      await run(
        build(duties: ProcessDuties(isProcessOwner: () => false)),
        const SeedBundledPlugins(),
      );
      expect(seed.seeds, 0);
    });

    test('בעלים זורע, גם כש-WindowRole אומר משני', () async {
      WindowRole.isSecondary = true;
      await run(
        build(duties: ProcessDuties(isProcessOwner: () => true)),
        const SeedBundledPlugins(),
      );
      expect(seed.seeds, 1);
    });

    test('בלי הזרקה — ProcessDuties.current, שנקרא בזמן האירוע', () async {
      WindowRole.isSecondary = false;
      final bloc = build();
      ProcessDuties.debugOverride = ProcessDuties(isProcessOwner: () => false);
      await run(bloc, const SeedBundledPlugins());
      expect(seed.seeds, 0);
    });
  });

  group('RescanDevelopmentManifests שואל את ProcessDuties', () {
    test('לא-בעלים אינו סורק', () async {
      WindowRole.isSecondary = false;
      await run(
        build(duties: ProcessDuties(isProcessOwner: () => false)),
        const RescanDevelopmentManifests(),
      );
      expect(repo.devPluginQueries, 0);
    });

    test('בעלים סורק', () async {
      WindowRole.isSecondary = true;
      await run(
        build(duties: ProcessDuties(isProcessOwner: () => true)),
        const RescanDevelopmentManifests(),
      );
      expect(repo.devPluginQueries, 1);
    });
  });

  test('ברירת המחדל שומרת על שער החלון המשני', () async {
    WindowRole.isSecondary = true;
    await run(build(), const SeedBundledPlugins());
    await run(build(), const RescanDevelopmentManifests());
    expect(seed.seeds, 0);
    expect(repo.devPluginQueries, 0);
  });
}
