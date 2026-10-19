import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/services/app_hang_report.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/crash_report_flow.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

import 'app_report_test_fakes.dart';

class _BlockedService extends FakeAppReportService {
  _BlockedService({
    this.status = AppReportDeliveryStatus.sent,
    this.throwFirst = false,
  });

  final AppReportDeliveryStatus status;
  final bool throwFirst;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<AppReportDeliveryResult> send(AppReport report) async {
    sent.add(report);
    if (sent.length == 1) {
      started.complete();
      await release.future;
      if (throwFirst) throw StateError('send failed');
    }
    return AppReportDeliveryResult(status: status, report: report);
  }
}

class _FailingRecordThrottle extends AutoCrashReportThrottle {
  _FailingRecordThrottle({required super.filePath});
  bool fail = true;

  @override
  Future<void> recordReported({
    required String signatureHash,
    required String appVersion,
  }) async {
    if (fail) {
      fail = false;
      throw StateError('throttle storage failed');
    }
    await super.recordReported(
      signatureHash: signatureHash,
      appVersion: appVersion,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('otzaria_hang_race_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  const hang = CrashCandidate.hang(
    signature: CrashSignature(
      exceptionType: 'AppHang',
      frames: ['otzaria.exe+0x1'],
    ),
  );

  CrashReportFlow flow(FakeAppReportService service) => CrashReportFlow(
    showPrompt: (_) async => true,
    service: service,
    collector: FakeAppReportCollector(),
    redactor: AppReportRedactor(environment: const {}),
    readMode: () => AppCrashReportMode.always,
    savedEmail: () => '',
    appVersion: '1',
    throttle: AutoCrashReportThrottle(filePath: '${tmp.path}/throttle.json'),
  );

  for (final status in AppReportDeliveryStatus.values) {
    test(
      'תקיעות מקבילות מאותה חתימה אינן עוקפות את המכסה אחרי $status',
      () async {
        final service = _BlockedService(status: status);
        Future<void> recover() => AppHangReport.onRecovered(
          const {'durationMs': 7000},
          readMode: () => AppCrashReportMode.always,
          detect: (_) async => hang,
          flow: flow(service),
        );
        final first = recover();
        await service.started.future;
        final second = recover();
        await pumpEventQueue(times: 100);
        service.release.complete();
        await Future.wait([first, second]);
        expect(service.sent, hasLength(1));
      },
    );
  }

  for (final alreadyReported in [0, 2]) {
    test(
      'חתימות שונות וקריסה בעלייה חולקות מכסה כשכבר דווחו $alreadyReported',
      () async {
        final throttle = AutoCrashReportThrottle(
          filePath: '${tmp.path}/throttle.json',
        );
        for (var i = 0; i < alreadyReported; i++) {
          await throttle.recordReported(
            signatureHash: 'prior-$i',
            appVersion: '1',
          );
        }
        final service = _BlockedService();
        final crash = CrashCandidate(
          previousSession: SessionLock(
            pid: 1,
            version: '1',
            startedAt: DateTime(2026),
          ),
          entries: const [],
          signature: const CrashSignature(
            exceptionType: 'StateError',
            frames: ['main.dart'],
          ),
          hasStartupStall: false,
          hasMinidump: false,
        );
        final first = flow(service).handle(crash);
        await service.started.future;
        final others = [
          for (var i = 0; i < 4; i++)
            flow(service).handle(
              CrashCandidate.hang(
                signature: CrashSignature(
                  exceptionType: 'AppHang',
                  frames: ['otzaria.exe+0x${i + 1}'],
                ),
              ),
            ),
        ];
        await pumpEventQueue(times: 100);
        service.release.complete();
        final outcomes = await Future.wait([first, ...others]);
        expect(service.sent, hasLength(3 - alreadyReported));
        expect(
          outcomes.where((o) => o == CrashReportOutcome.throttled),
          hasLength(2 + alreadyReported),
        );
        expect(
          service.sent.map((r) => r.signature!.hash).toSet(),
          hasLength(3 - alreadyReported),
        );
      },
    );
  }

  test('שגיאת שליחה משחררת את התור ואינה מונעת ניסיון נוסף', () async {
    final service = _BlockedService(throwFirst: true);
    final first = flow(service).handle(hang);
    final firstError = expectLater(first, throwsStateError);
    await service.started.future;
    final second = flow(service).handle(hang);
    service.release.complete();
    await firstError;
    expect(await second, CrashReportOutcome.sentAutomatically);
    expect(await flow(service).handle(hang), CrashReportOutcome.throttled);
    expect(service.sent, hasLength(2));
  });

  test('הגדרת never שנבחרה בזמן ההמתנה מונעת שליחה', () async {
    final service = _BlockedService();
    final first = flow(service).handle(hang);
    await service.started.future;
    var mode = AppCrashReportMode.always;
    final second =
        CrashReportFlow(
          showPrompt: (_) async => true,
          service: service,
          collector: FakeAppReportCollector(),
          redactor: AppReportRedactor(environment: const {}),
          readMode: () => mode,
          savedEmail: () => '',
          throttle: AutoCrashReportThrottle(
            filePath: '${tmp.path}/throttle.json',
          ),
        ).handle(
          const CrashCandidate.hang(
            signature: CrashSignature(
              exceptionType: 'AppHang',
              frames: ['other.dll+0x2'],
            ),
          ),
        );
    mode = AppCrashReportMode.never;
    service.release.complete();
    await first;
    expect(await second, CrashReportOutcome.ignored);
    expect(service.sent, hasLength(1));
  });

  test('חריגה ברישום המכסה אינה תוקעת את הדיווח הבא', () async {
    final service = FakeAppReportService();
    final throttle = _FailingRecordThrottle(
      filePath: '${tmp.path}/throttle.json',
    );
    CrashReportFlow recordFlow() => CrashReportFlow(
      showPrompt: (_) async => true,
      service: service,
      collector: FakeAppReportCollector(),
      redactor: AppReportRedactor(environment: const {}),
      readMode: () => AppCrashReportMode.always,
      savedEmail: () => '',
      appVersion: '1',
      throttle: throttle,
    );
    await expectLater(recordFlow().handle(hang), throwsStateError);
    expect(
      await recordFlow().handle(hang),
      CrashReportOutcome.sentAutomatically,
    );
    expect(await recordFlow().handle(hang), CrashReportOutcome.throttled);
    expect(service.sent, hasLength(2));
  });

  for (final collectorFails in [false, true]) {
    test(
      'דיווח ANR אוטומטי נשאר פרטי ומושחר גם כשאיסוף נכשל: $collectorFails',
      () async {
        final service = FakeAppReportService();
        await CrashReportFlow(
          showPrompt: (_) async => true,
          service: service,
          collector: FakeAppReportCollector(fail: collectorFails),
          redactor: AppReportRedactor(
            environment: const {'HOME': '/home/david'},
          ),
          readMode: () => AppCrashReportMode.always,
          savedEmail: () => '',
          appVersion: '1',
          throttle: AutoCrashReportThrottle(
            filePath: '${tmp.path}/throttle.json',
          ),
        ).handle(
          const CrashCandidate.hang(
            signature: CrashSignature(
              exceptionType: 'ANR',
              frames: ['org.otzaria.Main'],
            ),
            details: 'Android ANR\npath: /home/david/private.txt',
          ),
        );
        final report = service.sent.single;
        expect(report.description, isEmpty);
        expect(report.diagnostics?['hangDetails'], contains('Android ANR'));
        expect(
          report.toApiPayload().toString(),
          isNot(contains('/home/david')),
        );
        expect(
          report.diagnostics?['hangDetails'],
          contains('%USERPROFILE%/private.txt'),
        );
      },
    );
  }

  for (final collectorFails in [false, true]) {
    test(
      'מחסנית ANR מוצגת באבחון פרטי ומכבדת החרגה גם כשאיסוף נכשל: $collectorFails',
      () async {
        final bloc = AppReportBloc(
          trigger: AppReportTrigger.crashPrompt,
          service: FakeAppReportService(),
          collector: FakeAppReportCollector(fail: collectorFails),
          redactor: AppReportRedactor(
            environment: const {'HOME': '/home/david'},
          ),
          initialEmail: '',
          details: 'Android ANR\npath: /home/david/private.txt',
        );
        addTearDown(bloc.close);
        bloc.add(const AppReportAttachmentsRequested());
        final form =
            await bloc.stream.firstWhere((s) => s is AppReportEditing)
                as AppReportEditing;
        expect(form.diagnostics?['hangDetails'], contains('Android ANR'));
        expect(
          form.diagnostics?['hangDetails'],
          isNot(contains('/home/david')),
        );
        final edited = form.copyWith(description: 'גללתי בספר');
        final report = bloc.buildReport(edited);
        expect(report.description, 'גללתי בספר');
        expect(
          report.diagnostics?['hangDetails'],
          form.diagnostics?['hangDetails'],
        );
        final excluded = bloc.buildReport(
          edited.copyWith(includeDiagnostics: false, includeErrorLog: false),
        );
        expect(excluded.description, 'גללתי בספר');
        expect(excluded.diagnostics, isNull);
        expect(excluded.errorLog, isNull);
        expect(
          excluded.toApiPayload().toString(),
          isNot(contains('Android ANR')),
        );
      },
    );
  }
}
