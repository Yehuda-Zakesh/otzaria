import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/widgets/selection/viewport_aligned_selection_container.dart';

import '../../../test_helpers/memory_cache_provider.dart';

// גרירת בחירה כלפי מעלה נעצרה בפסקה שמתחת ולא נכנסה לפסקה שמעל, עד גרירת
// החלון. הרשימה מעוגנת בשורת הפתיחה (initialScrollIndex); הכותרת שלפניה
// יושבת ב-sliver ההפוך, וכשהיא נגללת כולה מעל החלון Flutter מדווח לה
// טרנספורם שגוי (בראש ה-viewport) — ואזור הבחירה ממיין אותה בין שתי
// הפסקאות וסורק אותה במקום את הפסקה שמעל.

const _title = 'ספר בדיקה';

final _content = <String>[
  '<h2>סימן קפח</h2>',
  '(א) <b>וכ"ש הירוק כו\'.</b> ${List.filled(40, 'מילה ארוכה בפסקה').join(' ')} '
      'שלא לראות כשהוא לח:',
  '(ב) <b>סמיכות והוא עב.</b> מבואר בב"י אם אינו לבן לגמרי אלא כמראה בגד '
      'לבן שנפל עליו אבק מותר דאין שחרורית כזה בא ממראה אדמומית:',
  '(ג) <b>או ירוק.</b> פי\' אותו שאבדה:',
  '(ד) <b>אין סומכין עליה.</b> לפי שאפשר שיש לה ספק וסברה שהוא טהור:',
];

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  /// פותח את הספר מעוגן בפסקה (א) — כך שהכותרת שלפניה ב-sliver ההפוך —
  /// וגולל מטה עד שהכותרת כולה מעל החלון (ועדיין בתחום המטמון).
  Future<TextBookTab> pumpScrolledView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = TextBookLoaded(
      book: TextBook(title: _title),
      showLeftPane: false,
      content: _content,
      fontSize: 18,
      showSplitView: false,
      showPageShapeView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: const [1],
      selectedIndex: null,
      pinLeftPane: false,
      searchText: '',
    );
    final textBookBloc = _TestTextBookBloc(state);
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(book: TextBook(title: _title), index: 1);
    addTearDown(textBookBloc.close);
    addTearDown(personalNotesBloc.close);
    addTearDown(settingsBloc.close);
    addTearDown(tab.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('he', 'IL')],
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: CombinedView(
              data: _content,
              openBookCallback: (_) {},
              openLeftPaneTab: (_, {searchText}) {},
              textSize: 18,
              showCommentaryAsExpansionTiles: false,
              tab: tab,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    unawaited(
      tab.lines.offsetController.animateScroll(
        offset: 450,
        duration: const Duration(milliseconds: 100),
      ),
    );
    await tester.pumpAndSettle();
    return tab;
  }

  Rect lineRect(WidgetTester tester, int lineIndex) =>
      tester.getRect(find.byKey(ValueKey('html_${_title}_$lineIndex')));

  /// ה-registrar של ה-Scrollable — הילדים שלו הם פריטי הרשימה, בסדר שבו
  /// אזור הבחירה סורק אותם.
  MultiSelectableSelectionContainerDelegate scrollableRegistrar(
    WidgetTester tester,
  ) {
    final ctx = tester.element(find.byType(SliverList).first);
    return SelectionContainer.maybeOf(ctx)!
        as MultiSelectableSelectionContainerDelegate;
  }

  Rect globalRectOf(Selectable selectable) {
    final box = selectable.boundingBoxes.reduce(
      (acc, rect) => acc.expandToInclude(rect),
    );
    return MatrixUtils.transformRect(selectable.getTransformTo(null), box);
  }

  testWidgets('פריט שנגלל כולו מעל החלון מדווח את מיקומו האמיתי', (
    tester,
  ) async {
    await pumpScrolledView(tester);
    expect(find.byKey(const ValueKey('html_${_title}_0')), findsNothing);
    final alefTop = lineRect(tester, 1).top;

    final registrar = scrollableRegistrar(tester);
    final tops = registrar.selectables.map((s) => globalRectOf(s).top).toList();
    // הכותרת (הפריט הראשון בסדר) חייבת לשבת מעל (א), לא בראש ה-viewport.
    expect(tops.first, lessThan(alefTop));
    expect(tops, orderedEquals([...tops]..sort()));
  });

  testWidgets('גרירה מ-(ב) כלפי מעלה נכנסת לפסקה (א)', (tester) async {
    await pumpScrolledView(tester);
    final alef = lineRect(tester, 1);
    final bet = lineRect(tester, 2);

    final gesture = await tester.startGesture(
      Offset(bet.center.dx, bet.top + 8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(Offset(alef.center.dx, alef.bottom - 100));
    await tester.pump();

    final registrar = scrollableRegistrar(tester);
    final selected = registrar.selectables
        .map((s) => s.getSelectedContent()?.plainText ?? '')
        .join();
    await gesture.up();
    await tester.pump();

    expect(selected, contains('שלא לראות כשהוא לח'));
    expect(selected, contains('(ב) סמיכות'));
  });

  testWidgets('תיבת הבחירה של פריט עוטפת את הטקסט שבתוכו', (tester) async {
    await pumpScrolledView(tester);
    for (var line = 1; line <= 4; line++) {
      final text = find.byKey(ValueKey('html_${_title}_$line'));
      if (text.evaluate().isEmpty) continue;
      final textRect = tester.getRect(text);
      final container = tester.getRect(
        find
            .ancestor(
              of: text,
              matching: find.byType(ViewportAlignedSelectionContainer),
            )
            .first,
      );
      expect(
        container.top <= textRect.top + 0.5 &&
            container.bottom >= textRect.bottom - 0.5,
        isTrue,
        reason: 'תיבת הבחירה $container אינה עוטפת את שורה $line ב-$textRect',
      );
    }
  });

  testWidgets('לחיצה משולשת בתחתית פסקה בוחרת אותה ולא את הפסקה שמתחת', (
    tester,
  ) async {
    await pumpScrolledView(tester);
    final bet = lineRect(tester, 2);
    final target = Offset(bet.center.dx, bet.bottom - 6);

    for (var i = 0; i < 3; i++) {
      await tester.tapAt(target, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 400));

    final registrar = scrollableRegistrar(tester);
    final selected = registrar.selectables
        .map((s) => s.getSelectedContent()?.plainText ?? '')
        .join();
    expect(selected, contains('סמיכות והוא עב'));
    expect(selected, isNot(contains('או ירוק')));
  });

  testWidgets('כל פריט ברשימה עטוף ב-ViewportAlignedSelectionContainer', (
    tester,
  ) async {
    await pumpScrolledView(tester);
    expect(
      find.byType(ViewportAlignedSelectionContainer),
      findsAtLeastNWidgets(3),
    );
  });
}
