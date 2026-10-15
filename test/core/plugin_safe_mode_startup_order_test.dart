import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'crash detection does not block reveal and plugin work waits for it',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final bootstrap = source.substring(
        source.indexOf('Future<void> _initializeRestartableRuntime()'),
        source.indexOf('Future<void> _runDeferredPluginSafeMode('),
      );
      expect(
        bootstrap,
        contains(
          'PluginSafeMode.ready = _runDeferredPluginSafeMode(previousPluginDecision);',
        ),
      );
      expect(bootstrap, isNot(contains('StartupCrashCounter.recordLaunch()')));
      expect(bootstrap, isNot(contains('await PluginSafeMode.ready')));
      final deferred = source.substring(
        source.indexOf('Future<void> _runDeferredPluginSafeMode('),
        source.indexOf('Future<void> _runDeferredStartupStability()'),
      );
      expect(
        deferred.indexOf('_mainWindowRevealedCompleter.future.timeout'),
        lessThan(deferred.indexOf('PluginSafeMode.initializeSession(')),
      );
      expect(deferred, contains("'pluginSafeMode'"));
      expect(deferred, contains('_logNonFatalInitializationError'));
    },
  );
}
