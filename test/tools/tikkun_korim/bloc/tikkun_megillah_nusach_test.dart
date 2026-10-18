import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/bloc/tikkun_korim_bloc.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';

import '../support/tikkun_fakes.dart';
import '../support/tikkun_fixtures.dart';

void main() {
  for (final initial in ['ashkenaz', 'sephard']) {
    test('החלפת נוסח באסתר, עם מטמון — מתחילים ב-$initial', () async {
      final loader = FakeTikkunTextLoader({'אסתר': readFixture('esther')});
      final data = FakeTikkunDataSource();
      final bloc = TikkunKorimBloc(
        repository: TikkunKorimRepository(
          engine: const TikkunEngineImpl(),
          data: data,
          textLoader: loader,
          computeRunner: syncComputeRunner,
        ),
        data: data,
        settingsStore: FakeTikkunSettingsStore(
          settings: TikkunSettings(
            startupMode: 'lastPosition',
            nusach: initial,
          ),
          navState: const TikkunNavState(
            section: TikkunSection.ketuvim,
            tanachBookId: 'ester',
          ),
        ),
        widthModelOf: (_) => fakeWidths,
        measureRoofs: (_) async {},
      );
      addTearDown(bloc.close);

      void expectNusach(String nusach) {
        final text = bloc.state.pages
            .expand((p) => p.lines)
            .expand((line) => line.words)
            .map((word) => stripNikud(word.nikud))
            .join(' ');
        expect(
          text,
          contains(
            'נפשם להשמיד ${nusach == 'ashkenaz' ? 'להרג' : 'ולהרג'} ולאבד',
          ),
        );
        expect(
          text,
          contains('לא עמד ${nusach == 'ashkenaz' ? 'בפניהם' : 'לפניהם'} כי'),
        );
      }

      final started = bloc.stream.firstWhere((s) => !s.isLoading);
      bloc.add(const TikkunStarted());
      await started;
      expectNusach(initial);

      for (final nusach in [
        initial == 'ashkenaz' ? 'sephard' : 'ashkenaz',
        initial,
      ]) {
        final previousRequest = bloc.state.scrollRequestId;
        final loaded = bloc.stream.firstWhere(
          (s) =>
              !s.isLoading &&
              s.settings.nusach == nusach &&
              s.scrollRequestId > previousRequest,
        );
        bloc.add(
          TikkunSettingsUpdated(bloc.state.settings.copyWith(nusach: nusach)),
        );
        await loaded.timeout(const Duration(seconds: 30));
        expectNusach(nusach);
      }
      expect(loader.requested, ['אסתר', 'אסתר']);
    });
  }
}
