import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';

class ReaderBackButton extends StatelessWidget {
  const ReaderBackButton({
    super.key,
    required this.lines,
    this.compact = false,
  });

  final LineScrollController lines;
  final bool compact;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: lines.canGoBack,
    builder: (context, available, _) => BarButton.icon(
      key: const ValueKey('reader-back-location'),
      tooltip: context.settingsText('חזרה למיקום הקודם'),
      icon: FluentIcons.arrow_left_24_regular,
      flipInRtl: true,
      compact: compact,
      onPressed: available ? () => unawaited(lines.goBack()) : null,
    ),
  );
}
