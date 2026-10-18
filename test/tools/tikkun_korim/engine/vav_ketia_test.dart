import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/engine/line_paginator.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tikkun_processor.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_vav_ketia.dart';
import 'package:otzaria/tools/tikkun_korim/view/vav_ketia_text.dart';

import '../support/tikkun_fixtures.dart';

void main() {
  for (final tradition in TikkunTradition.values) {
    test('${tradition.id} — סימון שלום אינו משנה טקסט או עימוד', () {
      final tokens = tokenizeBook(
        readFixture('bamidbar'),
        'במדבר',
        tradition: tradition,
      );
      final marked = tokens.where((t) => t.vavKetiaTradition != null).single;
      expect(marked.vavKetiaTradition, tradition);
      expect(marked.value, 'שָׁלֽוֹם');
      final lines = paginateAllTokens(tokens, const StamWidthModel.uniform());
      final word = lines
          .expand((l) => l.words)
          .where((w) => w.vavKetiaTradition != null)
          .single;
      expect(word.stam, 'שלום');
      expect(word.nikud, contains('שָׁלֽוֹם'));
      expect(word.copyWith(nikud: word.nikud).vavKetiaTradition, tradition);
      final withoutMarker = [
        for (final t in tokens) t.isWord ? TikkunToken.word(t.value!) : t,
      ];
      final original = paginateAllTokens(
        withoutMarker,
        const StamWidthModel.uniform(),
      );
      expect(
        [
          for (final l in lines) [for (final w in l.words) (w.stam, w.nikud)],
        ],
        [
          for (final l in original)
            [for (final w in l.words) (w.stam, w.nikud)],
        ],
      );
      final chapter = tokens
          .takeWhile((t) => !identical(t, marked))
          .where((t) => t.chapterNum != null)
          .last
          .chapterNum;
      final verse = tokens
          .takeWhile((t) => !identical(t, marked))
          .where((t) => t.verseNum != null)
          .last
          .verseNum;
      expect((chapter, verse), (25, 12));
    });
  }

  test('ברירת המחדל לפי המסורת והחלפה ידנית גוברת גם בתימן', () {
    expect(
      TikkunVavKetia.auto.codeFor(TikkunTradition.ashkenazSephard),
      0xE146,
    );
    expect(TikkunVavKetia.auto.codeFor(TikkunTradition.yemen), isNull);
    expect(
      TikkunVavKetia.regular.codeFor(TikkunTradition.ashkenazSephard),
      isNull,
    );
    expect(TikkunVavKetia.split.codeFor(TikkunTradition.yemen), 0xE143);
  });

  test('המרת הגליף מוגבלת למילה המסומנת ולגופן נתמך', () {
    for (final form in TikkunVavKetia.values) {
      expect(
        tikkunVavKetiaText(
          'שלום',
          tradition: null,
          form: form,
          family: 'AshkenaziStam',
        ),
        'שלום',
      );
      expect(
        tikkunVavKetiaText(
          'שלום',
          tradition: TikkunTradition.ashkenazSephard,
          form: form,
          family: 'Rubik',
        ),
        'שלום',
      );
      final shown = tikkunVavKetiaText(
        'שָׁלֽוֹם',
        tradition: TikkunTradition.ashkenazSephard,
        form: form,
        family: 'OtzariaAshuritNikud',
      );
      expect(restoreTikkunVavKetiaText(shown), 'שָׁלֽוֹם');
    }
  });
}
