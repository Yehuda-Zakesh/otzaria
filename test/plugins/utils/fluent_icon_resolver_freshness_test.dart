import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/plugins/gen_fluent_icon_map.dart';

void main() {
  test('fluent_icon_resolver.dart תואם לספריית פלואנט הנעוצה', () {
    expect(
      File(outputPath).readAsStringSync().replaceAll('\r\n', '\n'),
      buildFluentIconMap(Directory.current),
      reason: 'הרץ: dart run tool/plugins/gen_fluent_icon_map.dart',
    );
  });
}
