import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/widgets/feedback/indexing_warning.dart';

class _MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _PartialIndex extends Fake implements TantivyDataProvider {
  @override
  final ValueNotifier<bool> isInitialized = ValueNotifier(true);
  @override
  final ValueNotifier<bool> isIndexingDeferred = ValueNotifier(false);
  @override
  final Set<String> indexedFilePaths = {'some/indexed/book'};
}

const _inProgressText =
    'אינדקס החיפוש בתהליך עדכון. יתכן שחלק מהספרים לא יוצגו בתוצאות החיפוש.';

void main() {
  late _PartialIndex index;
  late _MockIndexingBloc bloc;

  setUp(() {
    // השמה בלי קריאה קודמת: קריאת המופע האמיתי הייתה פותחת את המנוע.
    TantivyDataProvider.instance = index = _PartialIndex();
    bloc = _MockIndexingBloc();
    // לפני עדכון הספרייה בעלייה האינדוקס עוד לא התחיל — המצב נשאר התחלתי.
    whenListen(
      bloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
  });

  Future<void> pumpWarning(WidgetTester tester, {bool dismissed = false}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<IndexingBloc>.value(
              value: bloc,
              child: IndexingWarningContainer(
                inProgressDismissed: dismissed,
                onDismiss: () {},
              ),
            ),
          ),
        ),
      );

  testWidgets(
    'אינדוקס שנדחה עד סיום עדכון הספרייה מציג את אזהרת האינדקס החלקי',
    (tester) async {
      await pumpWarning(tester);
      expect(find.text(_inProgressText), findsNothing);

      index.isIndexingDeferred.value = true;
      await tester.pump();
      expect(find.text(_inProgressText), findsOneWidget);

      index.isIndexingDeferred.value = false;
      await tester.pump();
      expect(find.text(_inProgressText), findsNothing);
    },
  );

  testWidgets('אזהרה שהמשתמש סגר אינה חוזרת בזמן הדחייה', (tester) async {
    index.isIndexingDeferred.value = true;
    await pumpWarning(tester, dismissed: true);
    expect(find.text(_inProgressText), findsNothing);
  });
}
