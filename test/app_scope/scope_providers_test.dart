import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/app_scope_providers.dart';
import 'package:otzaria/app_scope/external_activation_service.dart';
import 'package:otzaria/app_scope/window_scope_providers.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/plugins/bloc/plugin_updates_cubit.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  // שני חלונות תחת היקף תהליך אחד: ספק תהליך משותף, ספק חלון נפרד לכל אחד.
  // הבלוקים הנבדקים נבחרו כי הבנאים שלהם אינם נוגעים בדיסק או במנוע.
  testWidgets('חלונות אחים חולקים את ספקי התהליך ומקבלים ספקי חלון נפרדים', (
    tester,
  ) async {
    // מצב המסך המלא ההתחלתי נקרא מההגדרות ביצירת הקוביט.
    await Settings.init(cacheProvider: MemorySettingsCache());
    final contexts = <String, BuildContext>{};
    Widget window(String id) => Expanded(
      child: WindowScopeProviders(
        historyRepository: HistoryRepository(),
        child: Builder(
          builder: (context) {
            contexts[id] = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.pumpWidget(
      AppScopeProviders(
        settingsRepository: SettingsRepository(),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(children: [window('a'), window('b')]),
        ),
      ),
    );

    final a = contexts['a']!;
    final b = contexts['b']!;
    expect(
      identical(a.read<PluginUpdatesCubit>(), b.read<PluginUpdatesCubit>()),
      isTrue,
    );
    expect(
      identical(a.read<WorkStatusCubit>(), b.read<WorkStatusCubit>()),
      isFalse,
    );
    // מסך מלא שייך לחלון: F11 בחלון אחד אינו משנה את מצבו של אחר.
    final fullscreenA = a.read<WindowFullscreenCubit>();
    final fullscreenB = b.read<WindowFullscreenCubit>();
    expect(identical(fullscreenA, fullscreenB), isFalse);
    await fullscreenA.set(true);
    expect(fullscreenB.state, isFalse);
    expect(
      identical(
        a.read<ExternalActivationService>(),
        b.read<ExternalActivationService>(),
      ),
      isTrue,
    );

    // פירוק העץ סוגר את כל הבלוקים שנוצרו, כמו באתחול מחדש.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
