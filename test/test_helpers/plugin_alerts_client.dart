import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';

import '../tools/calendar/support/calendar_alerts_fakes.dart';

/// לקוח התראות ל-`PluginSystemBloc` בבדיקה: בעלים פרטי על [repository],
/// בלי הגדרות, בלי שידור ובלי הבעלים של התהליך.
CalendarAlertsClient pluginAlertsClientFor(
  PluginRegistryRepository repository,
) {
  final owner = CalendarAlertsOwner(
    store: MemoryAlertsStore(),
    pluginIds: RegistryPluginNotificationIdStore(repository),
    pluginEvents: () async => const [],
    dedupeDuplicates: false,
  );
  addTearDown(() async {
    await owner.idle;
    owner.dispose();
  });
  return LocalCalendarAlertsClient(owner);
}
