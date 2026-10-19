import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
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
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/text_book/view/widgets/selection_gutter_painter.dart';
import '../../../test_helpers/memory_cache_provider.dart';

// issue #875 — במצב קריאה רציפה כרטיס המפרשים נבנה בתחתית הפסקה הממוזגת
// כולה (מסכים שלמים מתחת לשורה שנלחצה). התיקון: פיצול רינדור הפסקה סביב
// השורה הנבחרת כך שהכרטיס מופיע מיד מתחתיה.

const _content = ['שורה ראשונה', 'שורה שניה', 'שורה שלישית'];

final _rashiLink = Link(
  heRef: 'רש"י על בראשית א',
  index1: 2,
  path2: 'commentary/רש"י.txt',
  index2: 7,
  connectionType: 'COMMENTARY',
);

TextBookLoaded _continuousState({
  int? selectedIndex,
  Map<int, List<Link>>? linksByLine,
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: _content,
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: false,
    activeCommentators: const ['רש"י'],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine:
        linksByLine ??
        {
          2: [_rashiLink],
        },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0, 1, 2],
    selectedIndex: selectedIndex,
    selectedIndices: selectedIndex == null ? const {} : {selectedIndex},
    pinLeftPane: false,
    searchText: '',
    continuousReadingMode: true,
  );
}

Future<_TestTextBookBloc> _pumpContinuousView(
  WidgetTester tester,
  TextBookLoaded state, {
  bool simple = false,
  bool isMainText = true,
  double textMaxWidth = -1,
}) async {
  final textBookBloc = _TestTextBookBloc(state);
  final personalNotesBloc = _TestPersonalNotesBloc(
    const PersonalNotesState.initial(),
  );
  final settingsBloc = _TestSettingsBloc(
    SettingsState.initial().copyWith(textMaxWidth: textMaxWidth),
  );
  final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 0);
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
          body: simple
              ? SimpleTextViewer(
                  content: _content,
                  fontSize: 18,
                  isMainText: isMainText,
                  highlightedIndices: isMainText ? null : const {1},
                  openBookCallback: (_) {},
                )
              : CombinedView(
                  data: _content,
                  openBookCallback: (_) {},
                  openLeftPaneTab: (_, {searchText}) {},
                  textSize: 18,
                  showCommentaryAsExpansionTiles: true,
                  tab: tab,
                ),
        ),
      ),
    ),
  );
  await tester.pump();
  return textBookBloc;
}

List<List<int>> _paragraphLineIndices(WidgetTester tester) => tester
    .widgetList<ContinuousReadingParagraph>(
      find.byType(ContinuousReadingParagraph),
    )
    .map(
      (paragraph) => paragraph.lines.map((line) => line.lineIndex).toList(),
    )
    .toList();

Finder _selectionMarkers() => find.byWidgetPredicate(
  (widget) =>
      (widget is CustomPaint &&
          (widget.painter is SelectionGutterPainter ||
              widget.foregroundPainter is SelectionGutterPainter)) ||
      (widget is ReaderLineGutter && widget.selectedLines.isNotEmpty),
);

Rect _textRect(WidgetTester tester, String text) {
  final paragraph = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .firstWhere((p) => p.text.toPlainText().contains(text));
  final offset = paragraph.text.toPlainText().indexOf(text);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + text.length),
      )
      .first
      .toRect();
  return Rect.fromPoints(
    paragraph.localToGlobal(box.topLeft),
    paragraph.localToGlobal(box.bottomRight),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final continuous in [false, true]) {
    testWidgets('צורת הדף: בחירה משאירה רקע יציב, רציף=$continuous', (
      tester,
    ) async {
      await _pumpContinuousView(
        tester,
        _continuousState(selectedIndex: 1, linksByLine: const {}).copyWith(
          continuousReadingMode: continuous,
        ),
        simple: true,
      );
      expect(_selectionMarkers(), findsOneWidget);
      final selected = find.descendant(
        of: _selectionMarkers(),
        matching: find.byType(AnimatedContainer),
      );
      expect(
        (tester.widget<AnimatedContainer>(selected).decoration as BoxDecoration)
            .color,
        isNull,
      );
    });
  }

  testWidgets('מפרש בצורת הדף שומר הדגשה מקומית בלי סמן בחירה ראשי', (
    tester,
  ) async {
    await _pumpContinuousView(
      tester,
      _continuousState(selectedIndex: 1),
      simple: true,
      isMainText: false,
    );
    expect(_selectionMarkers(), findsNothing);
    final theme = Theme.of(tester.element(find.byType(SimpleTextViewer)));
    expect(
      tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .any(
            (container) =>
                (container.decoration as BoxDecoration?)?.color ==
                AppSurfaces.paragraphSelectionBackground(theme.colorScheme),
          ),
      isTrue,
    );
  });

  testWidgets('קו הבחירה אינו מכסה דיו של אותיות בקצה פסקה רציפה', (
    tester,
  ) async {
    final font = File('fonts/FrankRuehlCLM-Medium.ttf').readAsBytesSync();
    final loader = FontLoader('FrankRuhlCLM')
      ..addFont(Future.value(ByteData.sublistView(font)));
    await loader.load();
    Future<({int width, List<int> bytes})> pixels() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find
            .ancestor(
              of: find.byType(ContinuousReadingParagraph),
              matching: find.byType(RepaintBoundary),
            )
            .first,
      );
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = (await image.toByteData())!.buffer.asUint8List().toList();
        final width = image.width;
        image.dispose();
        return (width: width, bytes: bytes);
      }))!;
    }

    await _pumpContinuousView(
      tester,
      _continuousState(linksByLine: const {}),
      textMaxWidth: 0,
    );
    await tester.pump(const Duration(milliseconds: 100));
    final before = await pixels();
    await _pumpContinuousView(
      tester,
      _continuousState(selectedIndex: 1, linksByLine: const {}),
      textMaxWidth: 0,
    );
    await tester.pump(const Duration(milliseconds: 100));
    final after = await pixels();
    expect(after.width, before.width);
    var edgeInk = 0;
    for (var i = 0; i < before.bytes.length; i += 4) {
      if ((i ~/ 4) % before.width < before.width - 3) continue;
      if (before.bytes[i] < 100 &&
          before.bytes[i + 1] < 100 &&
          before.bytes[i + 2] < 100 &&
          before.bytes[i + 3] == 255) {
        edgeInk++;
        expect(after.bytes.sublist(i, i + 4), before.bytes.sublist(i, i + 4));
      }
    }
    expect(
      edgeInk,
      greaterThan(0),
      reason: 'הטקסט חייב לגעת ברצועת הסמן כדי להוכיח שאין הסתרה',
    );
  });

  testWidgets('בחירת שורה באמצע פסקה — הפסקה מפוצלת והכרטיס מתחת לשורה', (
    tester,
  ) async {
    await _pumpContinuousView(tester, _continuousState(selectedIndex: 1));

    expect(
      _paragraphLineIndices(tester),
      [
        [0, 1],
        [2],
      ],
    );
    final card = find.byKey(const ValueKey('commentary_card_1'));
    expect(card, findsOneWidget);
    final cardRect = tester.getRect(card);
    final gutterFinder = _selectionMarkers();
    expect(gutterFinder, findsOneWidget);
    // הסמן מצויר מתחת לטקסט ונמתח רק לאורך השורה הנבחרת — לא על הכרטיס.
    expect(tester.widget<ReaderLineGutter>(gutterFinder).foreground, isFalse);
    final gutter = tester.renderObject<RenderReaderLineGutter>(gutterFinder);
    final bars = gutter
        .barRects()
        .map(
          (rect) => Rect.fromPoints(
            gutter.localToGlobal(rect.topLeft),
            gutter.localToGlobal(rect.bottomRight),
          ),
        )
        .toList();
    expect(bars, hasLength(1));
    expect(bars.single.overlaps(cardRect), isFalse);
    final lineRect = _textRect(tester, 'שורה שניה');
    expect(bars.single.top, lessThanOrEqualTo(lineRect.top + 0.5));
    expect(bars.single.bottom, greaterThanOrEqualTo(lineRect.bottom - 0.5));
    expect(
      bars.single.contains(_textRect(tester, 'שורה ראשונה').center),
      isFalse,
    );
  });

  testWidgets('לחיצה בתוך כרטיס המפרשים אינה משנה את בחירת השורה', (
    tester,
  ) async {
    final bloc = await _pumpContinuousView(
      tester,
      _continuousState(selectedIndex: 1),
    );
    final card = find.byKey(const ValueKey('commentary_card_1'));
    expect(card, findsOneWidget);
    final center = tester.getRect(card).center;
    await tester.tapAt(center, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(center, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tapAt(center, kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 400));

    expect(bloc.received.whereType<UpdateSelectedIndex>(), isEmpty);
    expect(card, findsOneWidget);
  });

  testWidgets('ללא בחירה — פסקה אחת שלמה ובלי כרטיס מפרשים', (tester) async {
    await _pumpContinuousView(tester, _continuousState(selectedIndex: null));

    expect(_paragraphLineIndices(tester), [
      [0, 1, 2],
    ]);
    expect(find.byKey(const ValueKey('commentary_card_1')), findsNothing);
  });

  testWidgets('שורה נבחרת בלי מפרשים — אין פיצול ואין כרטיס', (tester) async {
    await _pumpContinuousView(
      tester,
      _continuousState(selectedIndex: 1, linksByLine: const {}),
    );

    expect(_paragraphLineIndices(tester), [
      [0, 1, 2],
    ]);
    expect(find.byKey(const ValueKey('commentary_card_1')), findsNothing);
  });

  testWidgets('השורה האחרונה נבחרת — הכרטיס בסוף הפסקה בלי חלק שני ריק', (
    tester,
  ) async {
    await _pumpContinuousView(
      tester,
      _continuousState(
        selectedIndex: 2,
        linksByLine: {
          3: [_rashiLink],
        },
      ),
    );

    expect(_paragraphLineIndices(tester), [
      [0, 1, 2],
    ]);
    expect(find.byKey(const ValueKey('commentary_card_2')), findsOneWidget);
  });
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) => received.add(event));
  }

  final received = <TextBookEvent>[];

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
