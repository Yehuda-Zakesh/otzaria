/// קיצור מקלדת שתוסף מצהיר עליו — במניפסט (`contributes.startup.shortcuts`)
/// או בזמן ריצה (`app.registerShortcut`).
///
/// קיצור יכול להיות קשור לאחת משתי פעולות:
///  * **פעולת תפריט הקשר** — [contextMenuItemId] מפנה לפריט שתוסף הוסיף
///    לתפריט הלחיצה הימנית על טקסט (`reader.addContextMenuItem`); לחיצה על
///    הקיצור מפעילה את הפריט בדיוק כמו לחיצה ימנית עליו.
///  * **פקודה חופשית** — [command] הוא שם פקודה שנשלח לתוסף באירוע
///    `app.command`; התוסף מאזין ומבצע את הפקודה.
///
/// [key] הוא קיצור ברירת המחדל שהתוסף מציע. המשתמש יכול לשנות אותו או לבטלו
/// במסך הגדרות קיצורי המקשים. ערך ריק משמעו שהתוסף אינו מציע ברירת מחדל
/// והמשתמש מקצה קיצור בעצמו.
class PluginShortcut {
  /// מזהה ייחודי לקיצור בתוך התוסף.
  final String id;

  /// תווית תצוגה בעברית/אנגלית — מוצגת במסך הגדרות קיצורי המקשים.
  final String label;

  /// קיצור ברירת המחדל בפורמט קנוני (`ctrl+alt+x`), או ריק אם אין ברירת מחדל.
  final String key;

  /// שם פקודה חופשית — נשלחת לתוסף באירוע `app.command`.
  final String? command;

  /// מזהה פריט תפריט הקשר שהקיצור מפעיל (כמו לחיצה ימנית על הפריט).
  final String? contextMenuItemId;

  const PluginShortcut({
    required this.id,
    required this.label,
    this.key = '',
    this.command,
    this.contextMenuItemId,
  });

  /// פרסינג סובלני: שדות חסרים מקבלים ערך ברירת מחדל, ואם [command] או
  /// [contextMenuItemId] אינם מחרוזות — נחשבים כלא-קיימים.
  factory PluginShortcut.fromJson(Map<String, dynamic> json) {
    final command = json['command'];
    final contextMenuItemId = json['contextMenuItemId'];
    final key = json['key'];
    return PluginShortcut(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      key: key is String ? key : '',
      command: command is String && command.isNotEmpty ? command : null,
      contextMenuItemId:
          contextMenuItemId is String && contextMenuItemId.isNotEmpty
          ? contextMenuItemId
          : null,
    );
  }

  /// עותק עם [key] חדש — לשימוש ב-`app.updateShortcut`.
  PluginShortcut copyWith({String? key}) => PluginShortcut(
    id: id,
    label: label,
    key: key ?? this.key,
    command: command,
    contextMenuItemId: contextMenuItemId,
  );
}
