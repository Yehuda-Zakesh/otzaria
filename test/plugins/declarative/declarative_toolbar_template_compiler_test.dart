import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/declarative/compiler/declarative_toolbar_template_compiler.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

void main() {
  test('מקמפל כפתור ברירת מחדל ותפריט מהדורות בלבד', () {
    final templates = _compiler().compileAll('test.plugin', _templates());

    expect(templates, hasLength(2));
    expect(templates.first.baseItem.type, 'button');
    expect(templates.first.actionTemplate, isNotNull);
    expect(templates.last.baseItem.type, 'menu');
    expect(templates.last.childrenBinding!.maxItems, 10);
  });

  test('פקד מפוצל מקמפל גם פעולה ראשית וגם ילדים, וחייב את שניהם', () {
    final templates = _templates();
    final split = Map<String, dynamic>.from(templates.first)
      ..['type'] = 'split'
      ..['childrenBinding'] = templates.last['childrenBinding'];

    final compiled = _compiler().compileAll('test.plugin', [split]).single;
    expect(compiled.baseItem.type, 'split');
    expect(compiled.actionTemplate, isNotNull);
    expect(compiled.childrenBinding, isNotNull);

    final withoutChildren = Map<String, dynamic>.from(split)
      ..remove('childrenBinding');
    expect(
      () => _compiler().compileAll('test.plugin', [withoutChildren]),
      throwsA(isA<DeclarativeProgramException>()),
    );
  });

  test('פלט שאינו מוכר נדחה בזמן קומפילציה', () {
    final templates = _templates();
    (templates.first['binding'] as Map<String, dynamic>)['visibleOutput'] =
        'missing';

    expect(
      () => _compiler().compileAll('test.plugin', templates),
      _throwsProgramError('declarative.output_not_found'),
    );
  });

  test('פעולת פתיחת ספר דורשת הרשאה מוצהרת', () {
    expect(
      () => DeclarativeToolbarTemplateCompiler(
        declaredPermissions: const {'reader.toolbar'},
        programs: {'book-links': _program()},
      ).compileAll('test.plugin', _templates()),
      _throwsProgramError('declarative.permission_not_declared'),
    );
  });

  test('ילד תפריט אינו יכול לקרוא פלט גלובלי במקום את הפריט שלו', () {
    final templates = _templates();
    final children = templates.last['childrenBinding'] as Map<String, dynamic>;
    final itemTemplate = children['itemTemplate'] as Map<String, dynamic>;
    itemTemplate['title'] = {r'$output': 'defaultEdition.title'};

    expect(
      () => _compiler().compileAll('test.plugin', templates),
      _throwsProgramError('declarative.invalid_reference'),
    );
  });

  test('when נשמר על הפריט הדקלרטיבי ומסונן לפי התנאי', () {
    final templates = _templates();
    templates.first['when'] = {
      'setting': {'key': SettingsRepository.keyDarkMode, 'equals': true},
    };

    final compiled = _compiler().compileAll('test.plugin', templates).first;

    expect(compiled.baseItem.when, isNotNull);
    expect(compiled.baseItem.when!.settingKeys, {
      SettingsRepository.keyDarkMode,
    });

    final settings = <String, Object?>{};
    final evaluator = PluginConditionEvaluator.forTesting(
      settingReader: (key) => settings[key],
    );
    final registry = PluginToolbarRegistry.forTesting(evaluator: evaluator);
    registry.register('test.plugin', compiled.baseItem);

    expect(registry.getAll(), isEmpty);
    settings[SettingsRepository.keyDarkMode] = true;
    expect(registry.getAll(), hasLength(1));
  });

  test('כפתור קשור עם openPlugin: בלי action, והלחיצה פותחת את דף התוסף', () {
    final button = Map<String, dynamic>.from(_templates().first)
      ..remove('action')
      ..['openPlugin'] = true;

    final compiled = _compiler().compileAll('test.plugin', [button]).single;
    expect(compiled.openPlugin, isTrue);
    expect(compiled.actionTemplate, isNull);
    expect(compiled.childrenBinding, isNull);
    expect(compiled.visibleOutput, 'defaultEdition');

    // כפתור רגיל עם פעולה — openPlugin כבוי
    expect(
      _compiler().compileAll('test.plugin', _templates()).first.openPlugin,
      isFalse,
    );
  });

  test('openPlugin בכפתור קשור: סותר את action, רק בכפתור, ורק בוליאני', () {
    final both = Map<String, dynamic>.from(_templates().first)
      ..['openPlugin'] = true;
    expect(
      () => _compiler().compileAll('test.plugin', [both]),
      _throwsProgramError('declarative.invalid_toolbar_item'),
    );

    final menu = Map<String, dynamic>.from(_templates().last)
      ..['openPlugin'] = true;
    expect(
      () => _compiler().compileAll('test.plugin', [menu]),
      _throwsProgramError('declarative.invalid_toolbar_item'),
    );

    final notBool = Map<String, dynamic>.from(_templates().first)
      ..remove('action')
      ..['openPlugin'] = 'yes';
    expect(
      () => _compiler().compileAll('test.plugin', [notBool]),
      _throwsProgramError('declarative.invalid_toolbar_item'),
    );
  });

  test('שדה toolbar דקלרטיבי לא מוכר נדחה', () {
    final templates = _templates();
    templates.first['script'] = 'run()';

    expect(
      () => _compiler().compileAll('test.plugin', templates),
      _throwsProgramError('declarative.unknown_field'),
    );
  });
}

DeclarativeToolbarTemplateCompiler _compiler() =>
    DeclarativeToolbarTemplateCompiler(
      declaredPermissions: const {'reader.toolbar', 'reader.open'},
      programs: {'book-links': _program()},
    );

CompiledDeclarativeProgram _program() => const CompiledDeclarativeProgram(
  id: 'book-links',
  version: 1,
  triggers: ['reader.activeBookChanged'],
  when: null,
  commands: [],
  outputs: {'defaultEdition': null, 'editions': null},
  requiredPermissions: {},
);

List<Map<String, dynamic>> _templates() => [
  {
    'id': 'open-default',
    'type': 'button',
    'title': 'פתח במהדורת ברירת המחדל',
    'icon': 'book_24_regular',
    'contexts': ['reader-text', 'reader-pdf'],
    'binding': {
      'program': 'book-links',
      'visibleOutput': 'defaultEdition',
    },
    'action': {
      'type': 'reader.openBook',
      'args': {
        'identity': {r'$output': 'defaultEdition.identity'},
      },
    },
  },
  {
    'id': 'open-edition',
    'type': 'menu',
    'title': 'פתח מהדורה אחרת',
    'icon': 'book_24_regular',
    'binding': {
      'program': 'book-links',
      'visibleOutput': 'editions',
    },
    'childrenBinding': {
      'itemsOutput': 'editions',
      'maxItems': 10,
      'itemTemplate': {
        'id': {
          r'$concat': [
            'edition-',
            {r'$item': 'identity.id'},
          ],
        },
        'title': {r'$item': 'title'},
        'action': {
          'type': 'reader.openBook',
          'args': {
            'identity': {r'$item': 'identity'},
          },
        },
      },
    },
  },
];

Matcher _throwsProgramError(String code) => throwsA(
  isA<DeclarativeProgramException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);
