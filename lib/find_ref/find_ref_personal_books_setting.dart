import 'dart:async';

import 'package:otzaria/settings/engine/app_settings_store.dart';

/// מתג "כלול ספרים אישיים" של האיתור. מקור יחיד לדיאלוג, לקישורים ולסיור —
/// ברירת מחדל נפרדת במסלול אחד מסננת ספרים אישיים בשקט כשהמתג מוצג דלוק.
class FindRefPersonalBooksSetting {
  FindRefPersonalBooksSetting._();

  static const String key = 'key-find-ref-include-personal-books';

  static final StreamController<void> _changes =
      StreamController<void>.broadcast(sync: true);

  /// אחרי כל שמירה, כדי שדיאלוג פתוח בחלון אחר יתעדכן.
  static Stream<void> get changes => _changes.stream;

  static bool load() =>
      Settings.getValue<bool>(key, defaultValue: true) ?? true;

  static Future<void> save(bool value) async {
    await Settings.setValue<bool>(key, value);
    _changes.add(null);
  }
}
