import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ToolTab tool(String title) {
    final tab = ToolTab(toolId: 'org.example.plugin', title: title);
    PluginRestoreStateStore.instance.set(
      (pluginId: tab.toolId, instanceId: tab.instanceId),
      {'draft': title},
    );
    return tab;
  }

  test('עותק העברה מפוצל שומר מצב נפרד גם אחרי שחרור המקור', () {
    final source = CombinedTab(rightTab: tool('ימין'), leftTab: tool('שמאל'));
    final copy = OpenedTab.fromJson(source.toTransferJson()) as CombinedTab;
    expect(
      (copy.rightTab as ToolTab).instanceId,
      isNot((source.rightTab as ToolTab).instanceId),
    );
    source.dispose();
    expect(copy.rightTab.toJson()['pluginRestoreState'], contains('ימין'));
    expect(copy.leftTab.toJson()['pluginRestoreState'], contains('שמאל'));
    copy.dispose();
  });

  test('שחרור עותק שנדחה אינו מוחק את מצב המקור', () {
    final source = tool('טיוטה');
    OpenedTab.fromJson(source.toTransferJson()).dispose();
    expect(source.toJson()['pluginRestoreState'], contains('טיוטה'));
    source.dispose();
  });

  test('בדיקת יכולת העברה אינה מוחקת את מצב התוסף', () {
    final source = tool('טיוטה');
    expect(RunnerWindowChannel.canTransfer(source), isTrue);
    expect(source.toJson()['pluginRestoreState'], contains('טיוטה'));
    source.dispose();
  });
}
