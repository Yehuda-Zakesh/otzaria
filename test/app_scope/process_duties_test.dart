import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/windowing/window_role.dart';

void main() {
  late bool oldSecondary;

  setUp(() => oldSecondary = WindowRole.isSecondary);
  tearDown(() {
    WindowRole.isSecondary = oldSecondary;
    ProcessDuties.debugOverride = null;
  });

  test('ברירת המחדל היא בדיוק !WindowRole.isSecondary, בכל קריאה', () {
    final duties = ProcessDuties();
    WindowRole.isSecondary = false;
    expect(duties.isProcessOwner, isTrue);
    WindowRole.isSecondary = true;
    expect(duties.isProcessOwner, isFalse);
  });

  test('current עוקב אחרי WindowRole בלי הזרקה', () {
    WindowRole.isSecondary = true;
    expect(ProcessDuties.current.isProcessOwner, isFalse);
    WindowRole.isSecondary = false;
    expect(ProcessDuties.current.isProcessOwner, isTrue);
  });

  test('פרדיקט מוזרק גובר על WindowRole', () {
    WindowRole.isSecondary = false;
    expect(ProcessDuties(isProcessOwner: () => false).isProcessOwner, isFalse);
    WindowRole.isSecondary = true;
    expect(ProcessDuties(isProcessOwner: () => true).isProcessOwner, isTrue);
  });

  test('debugOverride מחליף את current, ו-null מחזיר את ברירת המחדל', () {
    WindowRole.isSecondary = false;
    final fake = ProcessDuties(isProcessOwner: () => false);
    ProcessDuties.debugOverride = fake;
    expect(ProcessDuties.current, same(fake));
    expect(ProcessDuties.current.isProcessOwner, isFalse);
    ProcessDuties.debugOverride = null;
    expect(ProcessDuties.current, isNot(same(fake)));
    expect(ProcessDuties.current.isProcessOwner, isTrue);
  });

  test('אין נעילת "פעם אחת": השאלה חוזרת על אותה תשובה', () {
    final duties = ProcessDuties(isProcessOwner: () => true);
    for (var i = 0; i < 3; i++) {
      expect(duties.isProcessOwner, isTrue);
    }
  });
}
