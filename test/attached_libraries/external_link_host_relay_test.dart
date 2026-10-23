import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/core/windowing/window_role.dart';

import '../test_helpers/fake_host_window.dart';

class _RecordingLinks extends ExternalLinkRepository {
  final calls = <String>[];

  @override
  void requestRebuild(String slug) {
    if (WindowRole.isSecondary) return super.requestRebuild(slug);
    calls.add('rebuild:$slug');
  }

  @override
  void requestResume(String slug) {
    if (WindowRole.isSecondary) return super.requestResume(slug);
    calls.add('resume:$slug');
  }
}

/// בניית אינדקס הקישורים רצה רק במארח. חלון משני שולח אליו את הפקודות,
/// ומציג את מצב הבנייה שהמארח משדר.
void main() {
  tearDown(() => WindowRole.isSecondary = false);

  group('חלון משני', () {
    late FakeHostWindow host;

    setUp(() {
      WindowRole.isSecondary = true;
      host = FakeHostWindow(namespace: 'otzaria.test.externallinks.relay')
        ..register();
    });

    tearDown(() => host.dispose());

    test('פקודות הבנייה נשלחות למארח', () async {
      final links = ExternalLinkRepository();

      links
        ..requestRebuild('dbA')
        ..requestResume('dbB')
        ..cancelBuild()
        ..pauseBuild()
        ..resumeBuild()
        ..setBuildEconomy(true);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final commands = host.ofType(ExternalLinkRepository.requestCommand);
      expect(
        [for (final c in commands) (c['command'], c['slug'], c['on'])],
        [
          ('requestRebuild', 'dbA', null),
          ('requestResume', 'dbB', null),
          ('cancel', null, null),
          ('pause', null, null),
          ('resume', null, null),
          ('economy', null, true),
        ],
      );
    });

    test('מצב המארח מוצג בחלון המשני', () async {
      final hostLinks = ExternalLinkRepository();
      WindowRole.isSecondary = false;
      hostLinks
        ..buildProgress.value = {
          'dbA': const ExternalLinkBuildProgress(done: 3, total: 10),
        }
        ..buildingSlugs.value = {'dbA'}
        ..incompleteSlugs.value = {'dbB'}
        ..tooLargeSlugs.value = {'dbC'}
        ..buildPaused.value = true;
      final snapshot =
          hostLinks.handleWindowRequest({
                'type': ExternalLinkRepository.requestState,
              })
              as Map<String, Object?>;
      host.respond = (_) => snapshot;
      WindowRole.isSecondary = true;

      final links = ExternalLinkRepository();
      await links.refreshFromHost();

      expect(links.buildProgress.value['dbA']?.done, 3);
      expect(links.buildProgress.value['dbA']?.total, 10);
      expect(links.buildingSlugs.value, {'dbA'});
      expect(links.incompleteSlugs.value, {'dbB'});
      expect(links.tooLargeSlugs.value, {'dbC'});
      expect(links.buildPaused.value, isTrue);

      // שידור הסיום מנקה את ההתקדמות.
      links.handleWindowRequest({
        'type': ExternalLinkRepository.requestState,
        'state': {'progress': {}, 'building': [], 'incomplete': []},
      });
      expect(links.buildProgress.value, isEmpty);
      expect(links.buildingSlugs.value, isEmpty);
      expect(links.incompleteSlugs.value, isEmpty);
    });

    test('חלון משני אינו מבצע פקודה של חלון אחר', () {
      final links = _RecordingLinks();
      expect(
        links.handleWindowRequest({
          'type': ExternalLinkRepository.requestCommand,
          'command': 'requestRebuild',
          'slug': 'dbA',
        }),
        isFalse,
      );
    });
  });

  group('מארח', () {
    test('מבצע פקודה שחלון משני שלח', () {
      final links = _RecordingLinks();
      for (final (command, slug) in [
        ('requestRebuild', 'dbA'),
        ('requestResume', 'dbB'),
      ]) {
        expect(
          links.handleWindowRequest({
            'type': ExternalLinkRepository.requestCommand,
            'command': command,
            'slug': slug,
          }),
          isTrue,
        );
      }
      expect(links.calls, ['rebuild:dbA', 'resume:dbB']);
    });

    test('פקודה לא מוכרת או בלי slug נדחית', () {
      final links = _RecordingLinks();
      for (final request in [
        {'command': 'drop'},
        {'command': 'requestRebuild'},
        {'command': 'economy'},
      ]) {
        expect(
          links.handleWindowRequest({
            'type': ExternalLinkRepository.requestCommand,
            ...request,
          }),
          isFalse,
        );
      }
      expect(links.calls, isEmpty);
    });
  });
}
