import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/indexing_work_status.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_overlay.dart';

void main() {
  testWidgets('Hebrew popup toggles economy only after native completion', (
    tester,
  ) async {
    final cubit = WorkStatusCubit();
    addTearDown(cubit.close);
    var economy = false;
    final requests = <bool>[];
    Completer<void>? gate;
    void publish() {
      final snapshot = economy;
      cubit.upsert(
        indexingWorkStatusItem(
          IndexingInProgress(
            booksProcessed: 1,
            totalBooks: 4,
            isEconomy: snapshot,
          ),
          onTogglePause: () {},
          onToggleEconomy: () async {
            requests.add(!snapshot);
            await gate?.future;
            economy = !snapshot;
            publish();
          },
        ),
      );
    }

    publish();
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: Stack(children: [WorkStatusOverlay()])),
          ),
        ),
      ),
    );
    expect(find.text('אינדוקס ספרים'), findsOneWidget);
    expect(find.text('מצב חסכוני'), findsOneWidget);
    expect(cubit.state.items['indexing']!.actions.last.emphasized, false);
    gate = Completer<void>();
    await tester.tap(find.text('מצב חסכוני'));
    await tester.pump();
    expect(requests, [true]);
    expect(cubit.state.items['indexing']!.actions.last.emphasized, false);
    gate.complete();
    await tester.pump();
    expect(cubit.state.items['indexing']!.actions.last.emphasized, true);
    gate = null;
    await tester.tap(find.text('מצב חסכוני'));
    await tester.pump();
    expect(requests, [true, false]);
    expect(cubit.state.items['indexing']!.actions.last.emphasized, false);
    expect(tester.takeException(), isNull);
  });
}
