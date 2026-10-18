import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_vav_ketia.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_stam_fonts.dart';

/// מחליף רק את גליף הווי״ו שסומן במנוע; בגופן אחר נשמר הטקסט העברי.
String tikkunVavKetiaText(
  String text, {
  required TikkunTradition? tradition,
  required TikkunVavKetia form,
  required String? family,
}) {
  if (tradition == null || !tikkunFamilyHasVavKetia(family)) return text;
  final code = form.codeFor(tradition);
  return code == null
      ? text
      : text.replaceFirst('ו', String.fromCharCode(code));
}
