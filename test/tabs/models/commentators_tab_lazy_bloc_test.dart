import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/workspaces/workspace.dart';

import '../../helpers/memory_settings_cache.dart';

/// כל שינוי בשולחנות עבודה מפענח ומקודד את כל הטאבים, ו-bloc שנבנה לטאב כזה
/// נרשם לזרם ההסתרות הסטטי ואינו משתחרר.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Map<String, dynamic> workspaceJson() {
    final tabs = [
      for (var i = 0; i < 5; i++)
        CommentatorsTab(
          sourceTab: TextBookTab(
            book: TextBook(title: 'ספר $i'),
            index: i * 7,
            commentators: const ['רש"י'],
          ),
          disposeSourceTabOnDispose: true,
          startIndex: i * 3,
        )..selectedCommentators = i.isEven ? const ['רמב"ן'] : null,
    ];
    final json = Workspace(name: 'א', tabs: tabs, activeTabIndex: 1).toJson();
    for (final tab in tabs) {
      tab.dispose();
    }
    return json;
  }

  test('פענוח, קידוד ושכפול של שולחן אינם בונים bloc לטאבי מפרשים', () {
    final json = workspaceJson();
    final previousObserver = Bloc.observer;
    final counter = _TextBookBlocCounter();
    Bloc.observer = counter;
    addTearDown(() => Bloc.observer = previousObserver);

    final workspace = Workspace.fromJson(json);
    workspace.toJson();
    final clones = workspace.tabs.map(OpenedTab.from).toList();

    expect(counter.created, 0);
    for (final tab in [...workspace.tabs, ...clones]) {
      tab.dispose();
    }
  });

  test('ה-JSON זהה לפני בניית ה-bloc ואחריה', () {
    final json = workspaceJson();
    final lazy = Workspace.fromJson(json);
    final eager = Workspace.fromJson(json);
    for (final tab in eager.tabs.cast<CommentatorsTab>()) {
      expect(tab.bloc.state, isA<TextBookInitial>());
      expect(tab.sourceTab.bloc.state, isA<TextBookInitial>());
    }

    expect(lazy.toJson(), eager.toJson());
    expect(lazy.toJson(), json);
    for (final tab in [...lazy.tabs, ...eager.tabs]) {
      tab.dispose();
    }
  });

  test('גישה ל-bloc אחרי dispose מחזירה bloc סגור', () async {
    final tab = CommentatorsTab(
      sourceTab: TextBookTab(book: TextBook(title: 'בראשית'), index: 0),
      disposeSourceTabOnDispose: true,
    );
    tab.dispose();
    final bloc = tab.bloc;
    await pumpEventQueue();
    expect(bloc.isClosed, isTrue);
  });
}

class _TextBookBlocCounter extends BlocObserver {
  int created = 0;

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    if (bloc is TextBookBloc) created++;
  }
}
