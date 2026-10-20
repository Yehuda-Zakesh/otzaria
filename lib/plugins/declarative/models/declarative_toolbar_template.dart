import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';

class CompiledDeclarativeChildrenBinding {
  final String itemsOutput;
  final Map<String, dynamic> itemTemplate;
  final int maxItems;

  const CompiledDeclarativeChildrenBinding({
    required this.itemsOutput,
    required this.itemTemplate,
    required this.maxItems,
  });
}

class CompiledDeclarativeToolbarTemplate {
  final PluginToolbarItem baseItem;
  final String programId;
  final String visibleOutput;
  final Map<String, dynamic>? actionTemplate;
  final CompiledDeclarativeChildrenBinding? childrenBinding;

  /// כפתור שלחיצה עליו פותחת את דף התוסף ומוסרת לו את אירוע הלחיצה, במקום
  /// פעולת host. סותר את [actionTemplate].
  final bool openPlugin;

  const CompiledDeclarativeToolbarTemplate({
    required this.baseItem,
    required this.programId,
    required this.visibleOutput,
    required this.actionTemplate,
    required this.childrenBinding,
    this.openPlugin = false,
  });
}
