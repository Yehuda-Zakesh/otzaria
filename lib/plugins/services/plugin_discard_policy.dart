import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/plugin_constants.dart';

/// מתי מפנים מופע קדמי מושהה, לפי פלטפורמה.
@immutable
class PluginDiscardLimits {
  const PluginDiscardLimits({
    required this.maxLiveSuspended,
    required this.maxSuspendedAge,
  });

  final int maxLiveSuspended;
  final Duration maxSuspendedAge;

  /// ב-Windows ההשהיה כבר מקצצת את ה-working set, והפינוי חוסך commit;
  /// בשאר הפלטפורמות אין הקפאה נייטיבית ודף מוסתר מחזיק את זיכרונו.
  static PluginDiscardLimits forPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.windows => const PluginDiscardLimits(
          maxLiveSuspended: 6,
          maxSuspendedAge: Duration(minutes: 60),
        ),
        TargetPlatform.android ||
        TargetPlatform.iOS => const PluginDiscardLimits(
          maxLiveSuspended: 2,
          maxSuspendedAge: Duration(minutes: 15),
        ),
        _ => const PluginDiscardLimits(
          maxLiveSuspended: 3,
          maxSuspendedAge: Duration(minutes: 30),
        ),
      };
}

/// מופע קדמי מושהה וחי, כפי שהמדיניות רואה אותו.
@immutable
class PluginDiscardCandidate {
  const PluginDiscardCandidate({
    required this.key,
    required this.suspendedAt,
    required this.exempt,
  });

  final PluginInstanceKey key;
  final DateTime suspendedAt;

  /// אסור לפנות אותו (שינויים לא שמורים, עבודה פתוחה וכו').
  final bool exempt;
}

/// בוחר אילו מופעים לפנות: בלחץ זיכרון — כל מי שמותר; אחרת מי שמושהה
/// יותר מהגיל המרבי, ומעבר לתקרה — הוותיקים ביותר. התקרה סופרת גם מוחרגים.
List<PluginInstanceKey> pickDiscardVictims(
  Iterable<PluginDiscardCandidate> suspended, {
  required DateTime now,
  required PluginDiscardLimits limits,
  bool memoryPressure = false,
}) {
  final all = suspended.toList(growable: false);
  final eligible = all.where((c) => !c.exempt).toList()
    ..sort((a, b) => a.suspendedAt.compareTo(b.suspendedAt));
  if (memoryPressure) return [for (final c in eligible) c.key];
  final victims = <PluginInstanceKey>[
    for (final c in eligible)
      if (now.difference(c.suspendedAt) >= limits.maxSuspendedAge) c.key,
  ];
  var overflow = all.length - victims.length - limits.maxLiveSuspended;
  for (final c in eligible) {
    if (overflow <= 0) break;
    if (victims.contains(c.key)) continue;
    victims.add(c.key);
    overflow--;
  }
  return victims;
}
