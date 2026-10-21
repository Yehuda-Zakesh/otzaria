import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';

/// חריגה על תרומת externalEditions לא תקינה — נזרקת ברישום ובוולידציה.
class PluginExternalEditionsException implements Exception {
  final String message;
  const PluginExternalEditionsException(this.message);

  @override
  String toString() => message;
}

/// עמודת מיון בטבלת המיפוי של תרומת מהדורות חיצוניות.
typedef ExternalEditionsOrder = ({String column, bool descending});

/// קונפיגורציית "מהדורות מקבילות חיצוניות" שתוסף מצהיר במניפסט
/// (`contributes.startup.externalEditions`): טבלת מיפוי במקור נתונים
/// שהתוסף הכריז עליו, שמקשרת מזהה ספק חיצוני למזהה ספר אוצריא.
///
/// לאוצריא אין ידע על אף ספק ספציפי — כל שמות הטבלה/עמודות/הספק מגיעים
/// מהתוסף, והשאילתות רצות דרך [PluginDatabaseService] תחת ה-policy של
/// המקור, כך שהתוסף אינו יכול להצביע על טבלאות שאינן מותרות לו ממילא.
class PluginExternalEditionsConfig {
  /// התוסף המצהיר — נדרש לשאילתות דרך שירות ה-DB (בדיקת הכרזת המקור).
  final InstalledPlugin plugin;

  final String id;

  /// שם הספק החיצוני — כמו בזהות `external.provider` של ספרי הספק.
  final String provider;

  /// מקור הנתונים (חייב להיות מוכרז ב-`contributes.databaseSources`).
  final String sourceId;

  /// טבלת המיפוי ועמודותיה: מזהה חיצוני ↔ מזהה ספר אוצריא.
  final String table;
  final String externalIdColumn;
  final String otzariaIdColumn;

  /// סדר איכות ההתאמה (למשל `is_best desc, confidence desc`).
  final List<ExternalEditionsOrder> orderBy;

  const PluginExternalEditionsConfig({
    required this.plugin,
    required this.id,
    required this.provider,
    required this.sourceId,
    required this.table,
    required this.externalIdColumn,
    required this.otzariaIdColumn,
    required this.orderBy,
  });
}

/// רישום תרומות המהדורות החיצוניות של תוספים — נצרך ע"י
/// ParallelEditionsService כדי לצרף מהדורות של ספקים חיצוניים ללחצן
/// "מהדורה מקבילה", בלי שאוצריא תכיר אף ספק ספציפי.
class PluginExternalEditionsRegistry {
  PluginExternalEditionsRegistry._();
  static final PluginExternalEditionsRegistry instance =
      PluginExternalEditionsRegistry._();

  @visibleForTesting
  PluginExternalEditionsRegistry.detached();

  static const int maxItemsPerPlugin = 2;
  static const int _maxOrderColumns = 4;

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_.\-]{1,64}$');
  static final RegExp _providerPattern = RegExp(r'^[a-z][a-z0-9\-]{0,63}$');
  static final RegExp _identifierPattern = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_]{0,63}$',
  );

  final Map<String, PluginExternalEditionsConfig> _byKey = {};

  /// כל הקונפיגורציות הרשומות, בסדר רישום יציב.
  List<PluginExternalEditionsConfig> get configs =>
      List.unmodifiable(_byKey.values);

  /// מפרש ורושם תרומה גולמית מהמניפסט. רישום חוזר של אותו מזהה מחליף את
  /// הקודם. זורק [PluginExternalEditionsException] על סכימה לא תקינה.
  void registerPayload(InstalledPlugin plugin, Map<String, dynamic> item) {
    final parsed = parsePayload(
      item,
      declaredSourceIds: {
        for (final source in plugin.manifest.databaseSources)
          if (source['id'] is String) source['id'] as String,
      },
    );
    final config = PluginExternalEditionsConfig(
      plugin: plugin,
      id: parsed.id,
      provider: parsed.provider,
      sourceId: parsed.sourceId,
      table: parsed.table,
      externalIdColumn: parsed.externalIdColumn,
      otzariaIdColumn: parsed.otzariaIdColumn,
      orderBy: parsed.orderBy,
    );
    final key = '${plugin.pluginId}/${config.id}';
    final ownedByPlugin = _byKey.keys
        .where((existing) => existing.startsWith('${plugin.pluginId}/'))
        .toSet();
    if (!ownedByPlugin.contains(key) &&
        ownedByPlugin.length >= maxItemsPerPlugin) {
      throw PluginExternalEditionsException(
        'externalEditions מוגבל ל-$maxItemsPerPlugin תרומות לתוסף',
      );
    }
    _byKey[key] = config;
  }

  void remove(String pluginId, String itemId) {
    _byKey.remove('$pluginId/$itemId');
  }

  void removePlugin(String pluginId) {
    _byKey.removeWhere((key, _) => key.startsWith('$pluginId/'));
  }

  /// פרסינג ואימות בלבד (ללא רישום) — משמש גם את הוולידציה בעת אריזה,
  /// שם עדיין אין InstalledPlugin ולכן המקורות המוכרזים מגיעים כפרמטר.
  static ParsedExternalEditionsPayload parsePayload(
    Map<String, dynamic> item, {
    required Set<String> declaredSourceIds,
  }) {
    String requireField(String field, RegExp pattern, String description) {
      final value = item[field];
      if (value is! String || !pattern.hasMatch(value)) {
        throw PluginExternalEditionsException(
          'externalEditions.$field חייב להיות $description',
        );
      }
      return value;
    }

    final id = requireField('id', _idPattern, 'מזהה (עד 64 תווים)');
    final provider = requireField(
      'provider',
      _providerPattern,
      'שם ספק באותיות קטנות (עד 64 תווים)',
    );
    final sourceId = requireField('sourceId', _identifierPattern, 'שם מקור');
    final table = requireField('table', _identifierPattern, 'שם טבלה');
    final externalIdColumn = requireField(
      'externalIdColumn',
      _identifierPattern,
      'שם עמודה',
    );
    final otzariaIdColumn = requireField(
      'otzariaIdColumn',
      _identifierPattern,
      'שם עמודה',
    );
    if (externalIdColumn == otzariaIdColumn) {
      throw const PluginExternalEditionsException(
        'externalEditions: externalIdColumn ו-otzariaIdColumn חייבים להיות '
        'עמודות שונות',
      );
    }
    if (!declaredSourceIds.contains(sourceId)) {
      throw PluginExternalEditionsException(
        'externalEditions.sourceId "$sourceId" אינו מוכרז '
        'ב-contributes.databaseSources',
      );
    }

    final orderByRaw = item['orderBy'];
    final orderBy = <ExternalEditionsOrder>[];
    if (orderByRaw != null) {
      if (orderByRaw is! List || orderByRaw.length > _maxOrderColumns) {
        throw const PluginExternalEditionsException(
          'externalEditions.orderBy חייב להיות מערך של עד 4 עמודות',
        );
      }
      for (final entry in orderByRaw) {
        if (entry is! Map) {
          throw const PluginExternalEditionsException(
            'externalEditions.orderBy מכיל ערך שאינו אובייקט',
          );
        }
        final column = entry['column'];
        final direction = entry['direction'];
        if (column is! String || !_identifierPattern.hasMatch(column)) {
          throw const PluginExternalEditionsException(
            'externalEditions.orderBy.column חייב להיות שם עמודה',
          );
        }
        if (direction != null && direction != 'asc' && direction != 'desc') {
          throw const PluginExternalEditionsException(
            'externalEditions.orderBy.direction חייב להיות asc או desc',
          );
        }
        orderBy.add((column: column, descending: direction == 'desc'));
      }
    }

    return ParsedExternalEditionsPayload(
      id: id,
      provider: provider,
      sourceId: sourceId,
      table: table,
      externalIdColumn: externalIdColumn,
      otzariaIdColumn: otzariaIdColumn,
      orderBy: orderBy,
    );
  }
}

/// תוצאת פרסינג של תרומת externalEditions — לפני קשירה לתוסף מותקן.
class ParsedExternalEditionsPayload {
  final String id;
  final String provider;
  final String sourceId;
  final String table;
  final String externalIdColumn;
  final String otzariaIdColumn;
  final List<ExternalEditionsOrder> orderBy;

  const ParsedExternalEditionsPayload({
    required this.id,
    required this.provider,
    required this.sourceId,
    required this.table,
    required this.externalIdColumn,
    required this.otzariaIdColumn,
    required this.orderBy,
  });
}
