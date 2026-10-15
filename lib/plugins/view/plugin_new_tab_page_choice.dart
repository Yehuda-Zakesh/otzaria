import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_service.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

Future<bool> choosePluginNewTabPage(
  BuildContext context,
  InstalledPlugin plugin,
  PluginRegistryRepository repository,
) async {
  final ownerId = await PluginNewTabPageService.instance.ownerId(repository);
  if (!context.mounted) return false;
  if (ownerId != null && ownerId != plugin.pluginId) {
    final owner = await repository.getPlugin(ownerId);
    if (!context.mounted) return false;
    final replace = await showTwoActionsDialog(
      context: context,
      title: context.settingsText('בחירת תוסף לכפתור לשונית חדשה (+)'),
      content: context.settingsText(
        'כפתור "+" ניתן לתוסף "{owner}". למי להעניק את הכפתור? ניתן לשנות את הבחירה בהרשאות התוספים.',
        args: {'owner': owner?.name ?? ownerId},
      ),
      cancelText: context.settingsText(
        'השאר אצל {plugin}',
        args: {'plugin': owner?.name ?? ownerId},
      ),
      confirmText: context.settingsText(
        'הענק ל{plugin}',
        args: {'plugin': plugin.name},
      ),
    );
    if (replace != true || !context.mounted) return false;
  }
  return PluginNewTabPageService.instance.grant(
    plugin.pluginId,
    repository,
    expectedOwner: ownerId,
  );
}

Future<void> notifyPluginNewTabPageConflict(
  InstalledPlugin plugin,
  String ownerId,
  PluginRegistryRepository repository,
) async {
  final owner = await repository.getPlugin(ownerId);
  UiSnack.showWithAction(
    message: PluginMessages.newTabPageOccupied(
      plugin.name,
      owner?.name ?? ownerId,
    ),
    actionLabel: PluginMessages.chooseNewTabPagePlugin,
    duration: const Duration(seconds: 12),
    onAction: () async {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      try {
        await choosePluginNewTabPage(context, plugin, repository);
      } catch (error) {
        UiSnack.showError(PluginMessages.updatePermissionError(error));
      }
    },
  );
}
