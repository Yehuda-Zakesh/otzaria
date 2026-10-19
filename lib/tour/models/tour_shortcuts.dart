// לתחזוקת הסיור המודרך ראו: docs/guided_tour_developer_guide.md

import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tour/models/tour_step.dart';

/// תוויות הניווט עם מפתח ההגדרה של הקיצור של כל אחת. התוויות זהות לאלו
/// שבסרגל הניווט, כדי שהתרגום יהיה אחד.
const List<(String label, String settingKey)> _navigationShortcuts = [
  ('ספרייה', 'key-shortcut-open-library-browser'),
  ('איתור', 'key-shortcut-open-find-ref'),
  ('עיון', 'key-shortcut-open-reading-screen'),
  ('חיפוש', 'key-shortcut-open-new-search'),
  ('כלים', 'key-shortcut-open-more'),
  ('הגדרות', 'key-shortcut-open-settings'),
];

const Map<TourShortcutHint, String> _singleShortcuts = {
  TourShortcutHint.findRef: 'key-shortcut-open-find-ref',
  TourShortcutHint.reading: 'key-shortcut-open-reading-screen',
  TourShortcutHint.search: 'key-shortcut-open-new-search',
  TourShortcutHint.tools: 'key-shortcut-open-more',
  TourShortcutHint.settings: 'key-shortcut-open-settings',
};

/// הטקסט שממלא את `{shortcut}` בגוף שלב הסיור, או `null` כשאין קיצור.
///
/// [context] - דרוש לתרגום תוויות הניווט לשפת ההגדרות.
String? tourShortcutText(BuildContext context, TourShortcutHint hint) {
  if (hint == TourShortcutHint.none) return null;
  if (hint == TourShortcutHint.mainNavigation) {
    return _navigationShortcuts
        .map(
          (entry) =>
              '${context.settingsText(entry.$1)} '
              '${_read(entry.$2)}',
        )
        .join(' · ');
  }
  return _read(_singleShortcuts[hint]!);
}

String _read(String key) => ShortcutHelper.formatShortcutForDisplay(
  Settings.getValue<String>(key) ??
      ShortcutValidator.defaultShortcuts[key] ??
      '',
);
