import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

/// הודעה קבועה מעל הקורא כל עוד יש בלשונית סשן תיקון של תוסף.
class PluginCorrectionSessionBanner extends StatelessWidget {
  static String modeText(String ownerName) =>
      'מצב תיקון של התוסף ‹$ownerName› — הנוסח המוצג כולל הצעות מקומיות; '
      'הספר אינו משתנה';
  static const savedText = 'הטיוטה נשמרה';
  static const savingText = 'שומר טיוטה…';
  static const failedText = 'שמירת הטיוטה נכשלה';
  static const retryText = 'נסה שוב';
  static const pageShapeText = 'התיקונים מוסתרים בצורת הדף';
  static const endText = 'סיום עריכה';

  final String tabId;
  final bool pageShape;
  final PluginCorrectionSessionService? service;

  const PluginCorrectionSessionBanner({
    super.key,
    required this.tabId,
    this.pageShape = false,
    this.service,
  });

  @override
  Widget build(BuildContext context) {
    final sessions = service ?? PluginCorrectionSessionService.instance;
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final ownerName = sessions.ownerNameForTab(tabId);
        final status = sessions.draftStatusForTab(tabId);
        if (ownerName == null || status == null) return const SizedBox.shrink();
        final colorScheme = Theme.of(context).colorScheme;
        final textStyle = TextStyle(color: colorScheme.onTertiaryContainer);
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer,
              borderRadius: AppTokens.borderRadiusAll,
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.edit_24_regular,
                  color: colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        modeText(ownerName),
                        style: textStyle.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(switch (status) {
                        PluginCorrectionDraftStatus.saved => savedText,
                        PluginCorrectionDraftStatus.saving => savingText,
                        PluginCorrectionDraftStatus.failed => failedText,
                      }, style: textStyle),
                      if (pageShape) Text(pageShapeText, style: textStyle),
                    ],
                  ),
                ),
                if (status == PluginCorrectionDraftStatus.failed)
                  ActionButton.ghost(
                    text: retryText,
                    onPressed: sessions.retryDraftWrites,
                  ),
                const SizedBox(width: 8),
                ActionButton.neutral(
                  text: endText,
                  onPressed: () => sessions.endByUser(tabId),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
