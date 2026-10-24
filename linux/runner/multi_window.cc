#include "multi_window.h"

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstdint>
#include <cstdlib>
#include <cstring>

#include "main_hide_policy.h"

namespace {

// החלון הראשי כפי שה-runner מכיר אותו. חלונות נוספים הם חלונות Dart באותו
// מנוע, וה-runner אינו מחזיק עליהם רשומה.
struct MainWindow {
  GtkWindow* window = nullptr;
  FlMethodChannel* channel = nullptr;  // otzaria/multiwindow
  // Dart הסתיר את הראשי (`closeSelf`); הוא חוזר ב-`raiseSelf`/שחזור.
  bool closed_by_user = false;
};

MainWindow& Main() {
  static MainWindow main_window;
  return main_window;
}

// חלון Dart (ריבוי תצוגות) גלוי: חלון עליון שאינו הראשי ותוכנו FlView.
bool HasVisibleDartViewWindow() {
  GList* toplevels = gtk_window_list_toplevels();
  bool found = false;
  for (GList* item = toplevels; item != nullptr && !found; item = item->next) {
    GtkWindow* window = GTK_WINDOW(item->data);
    if (window == Main().window ||
        !gtk_widget_get_visible(GTK_WIDGET(window))) {
      continue;
    }
    GtkWidget* child = gtk_bin_get_child(GTK_BIN(window));
    found = child != nullptr && FL_IS_VIEW(child);
  }
  g_list_free(toplevels);
  return found;
}

void RespondSuccess(FlMethodCall* call, FlValue* value) {
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond_success(call, value, &error)) {
    g_warning("otzaria/multiwindow: respond failed: %s", error->message);
  }
}

// ── הסתרה ושחזור ────────────────────────────────────────────────────────

void Hide() {
  MainWindow& main_window = Main();
  if (main_window.closed_by_user || main_window.window == nullptr) return;
  main_window.closed_by_user = true;
  gtk_widget_hide(GTK_WIDGET(main_window.window));
  // הראשי הוא חלון ה-runner היחיד, ולכן אחרי ההסתרה לא נשאר אף אחד.
  if (!ShouldExitOnWindowHide(0, HasVisibleDartViewWindow())) return;
  // ⚠️ נסגר החלון האחרון בלי שעבר את מסלול הסגירה של Dart. אין מה לשטוף — רק לצאת.
  // לא `g_application_quit`: יציאה מלולאת GTK הורסת את ה-FlView על ה-thread הראשי.
  exit(0);
}

void Show() {
  MainWindow& main_window = Main();
  if (main_window.window == nullptr) return;
  main_window.closed_by_user = false;
  gtk_widget_show(GTK_WIDGET(main_window.window));
  gtk_window_present(main_window.window);
}

bool RestoreLastClosedWindow() {
  if (!Main().closed_by_user) return false;
  Show();
  return true;
}

void OnMainWindowDestroyed(GtkWidget*, gpointer) {
  MainWindow& main_window = Main();
  g_clear_object(&main_window.channel);
  main_window.window = nullptr;
}

// ── הערוץ ──────────────────────────────────────────────────────────────

void MultiWindowMethodCallCb(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);

  if (strcmp(method, "closeSelf") == 0) {
    // בדחייה: הקריאה מגיעה מתוך ריצת ה-Dart של המנוע הזה.
    g_idle_add(
        [](gpointer) -> gboolean {
          Hide();
          return G_SOURCE_REMOVE;
        },
        nullptr);
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "raiseSelf") == 0) {
    if (Main().closed_by_user) {
      Show();
    } else if (Main().window != nullptr) {
      gtk_window_present(Main().window);
    }
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "mainWindowHandle") == 0) {
    // ה-GtkWindow* של הראשי, לחלונות Dart; ל-window_manager אין getId ב-Linux.
    if (Main().window == nullptr) {
      RespondSuccess(call, nullptr);
      return;
    }
    g_autoptr(FlValue) value =
        fl_value_new_int(reinterpret_cast<intptr_t>(Main().window));
    RespondSuccess(call, value);
    return;
  }
  if (strcmp(method, "restoreLastClosedWindow") == 0) {
    g_autoptr(FlValue) value = fl_value_new_bool(RestoreLastClosedWindow());
    RespondSuccess(call, value);
    return;
  }
  // ⚠️ כולל את מתודות הגרירה, שאינן ממומשות ב-Linux. הצד של Dart עוטף כל אחת
  // וממפה כשל ל"לא ידוע".
  g_autoptr(GError) error = nullptr;
  fl_method_call_respond_not_implemented(call, &error);
}

}  // namespace

void otzaria_multi_window_register_main(GtkWindow* window, FlView* view) {
  MainWindow& main_window = Main();
  if (main_window.window != nullptr) return;
  main_window.window = window;
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  main_window.channel = fl_method_channel_new(messenger, "otzaria/multiwindow",
                                              FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      main_window.channel, MultiWindowMethodCallCb, nullptr, nullptr);
  g_signal_connect(window, "destroy", G_CALLBACK(OnMainWindowDestroyed),
                   nullptr);
}

void otzaria_apply_window_titlebar(GtkWindow* window) {
  // Header bar ב-GNOME, כי זה הסגנון המקובל שם; ב-X11 עם מנהל חלונות
  // אחר — כותרת מסורתית, למקרה של פריסה חריגה (tiling). ב-Wayland מניחים
  // ש-header bar יעבוד.
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "אוצריא");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "אוצריא");
  }
}
