#include "splash_window.h"

#include <limits.h>
#include <stdint.h>
#include <unistd.h>

#include <string>

#include "../../native/splash/splash_timeline.h"

namespace {

namespace tl = splash_timeline;

// הסמל הסטטי (הפחתת תנועה, או גיבוי) בפיקסלים לוגיים (תואם ל-Windows/macOS).
constexpr int kIconSize = 160;
// פריים האנימציה: בגודל הזה הספר הפתוח בפריים האחרון זהה בגודלו לסמל הסטטי.
constexpr int kFrameSize = 177;
// זמן תצוגה מינימלי (מונע הבזק אם החשיפה מגיעה מוקדם).
constexpr gint64 kMinDisplayUs = 800 * 1000;  // 800ms במיקרו-שניות

struct LoadRequest {
  std::string path;
  bool strip;
  int size;   // בפיקסלים פיזיים: צד הפריים הסטטי
  int scale;  // מקדם ה-HiDPI של GTK
};

struct Loaded {
  cairo_surface_t* surface;
  int frames;
};

GtkWidget* g_splash = nullptr;
cairo_surface_t* g_surface = nullptr;  // כל הפריימים זה מתחת לזה, מוכפלי-אלפא
int g_frames = 0;
int g_logical = 0;
bool g_animate = false;
bool g_loading = false;
bool g_close_requested = false;
bool g_closing = false;
gint64 g_shown_at_us = 0;
gint64 g_close_at_us = 0;
guint g_tick_id = 0;
tl::Pose g_pose = {0, 0};
tl::Pose g_close_from = {0, 0};

// נתיב קובץ ההרצה (תיקייה), כדי לאתר את data/ שלצדו.
std::string ExecutableDir() {
  char buf[PATH_MAX];
  ssize_t len = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (len <= 0) {
    return std::string();
  }
  buf[len] = '\0';
  std::string path(buf);
  size_t pos = path.find_last_of('/');
  if (pos == std::string::npos) {
    return std::string();
  }
  return path.substr(0, pos);
}

// "gtk-enable-animations" כבוי = הפחתת תנועה.
bool AnimationsEnabled() {
  GtkSettings* settings = gtk_settings_get_default();
  if (settings == nullptr) return true;
  gboolean enabled = TRUE;
  g_object_get(settings, "gtk-enable-animations", &enabled, nullptr);
  return enabled != FALSE;
}

// pixbuf → משטח cairo מוכפל-אלפא, בזיכרון בלבד (בטוח מחוץ ל-thread הראשי).
cairo_surface_t* SurfaceFromPixbuf(GdkPixbuf* pixbuf) {
  const int w = gdk_pixbuf_get_width(pixbuf);
  const int h = gdk_pixbuf_get_height(pixbuf);
  const int channels = gdk_pixbuf_get_n_channels(pixbuf);
  const int src_stride = gdk_pixbuf_get_rowstride(pixbuf);
  const guchar* src = gdk_pixbuf_read_pixels(pixbuf);
  if (channels < 3) return nullptr;
  cairo_surface_t* surface =
      cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
  if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(surface);
    return nullptr;
  }
  cairo_surface_flush(surface);
  unsigned char* dst = cairo_image_surface_get_data(surface);
  const int dst_stride = cairo_image_surface_get_stride(surface);
  for (int y = 0; y < h; ++y) {
    const guchar* s = src + static_cast<size_t>(y) * src_stride;
    uint32_t* d = reinterpret_cast<uint32_t*>(
        dst + static_cast<size_t>(y) * dst_stride);
    for (int x = 0; x < w; ++x, s += channels) {
      const uint32_t a = channels == 4 ? s[3] : 255;
      const uint32_t r = (s[0] * a + 127) / 255;
      const uint32_t g = (s[1] * a + 127) / 255;
      const uint32_t b = (s[2] * a + 127) / 255;
      d[x] = (a << 24) | (r << 16) | (g << 8) | b;
    }
  }
  cairo_surface_mark_dirty(surface);
  return surface;
}

void FreeLoaded(gpointer data) {
  Loaded* loaded = static_cast<Loaded*>(data);
  if (loaded->surface != nullptr) cairo_surface_destroy(loaded->surface);
  delete loaded;
}

void FreeRequest(gpointer data) { delete static_cast<LoadRequest*>(data); }

// פענוח ב-thread של GTask: ה-thread הראשי (שמאתחל את המנוע) לא ממתין לו.
void LoadInThread(GTask* task, gpointer, gpointer data, GCancellable*) {
  const LoadRequest* req = static_cast<const LoadRequest*>(data);
  GError* error = nullptr;
  GdkPixbuf* pixbuf =
      req->strip ? gdk_pixbuf_new_from_file(req->path.c_str(), &error)
                 : gdk_pixbuf_new_from_file_at_scale(
                       req->path.c_str(), req->size, req->size, TRUE, &error);
  if (pixbuf == nullptr) {
    g_task_return_error(task, error);
    return;
  }
  const int w = gdk_pixbuf_get_width(pixbuf);
  const int h = gdk_pixbuf_get_height(pixbuf);
  int frames = 1;
  if (req->strip) {
    frames = (w > 0 && h % w == 0) ? h / w : 0;
  }
  cairo_surface_t* surface = frames > 0 ? SurfaceFromPixbuf(pixbuf) : nullptr;
  g_object_unref(pixbuf);
  if (surface == nullptr) {
    g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
                            "splash image");
    return;
  }
  g_task_return_pointer(task, new Loaded{surface, frames}, FreeLoaded);
}

void StartLoad(bool strip, int scale);

void DestroySplash() {
  if (g_splash != nullptr) {
    if (g_tick_id != 0) {
      gtk_widget_remove_tick_callback(g_splash, g_tick_id);
      g_tick_id = 0;
    }
    gtk_widget_destroy(g_splash);
    g_splash = nullptr;
  }
  if (g_surface != nullptr) {
    cairo_surface_destroy(g_surface);
    g_surface = nullptr;
  }
}

gboolean DestroyOnIdle(gpointer) {
  DestroySplash();
  return G_SOURCE_REMOVE;
}

// מצייר את הפריים הנוכחי (g_pose) על רקע שקוף.
gboolean OnDraw(GtkWidget*, cairo_t* cr, gpointer) {
  cairo_save(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
  cairo_paint(cr);
  cairo_restore(cr);
  if (g_surface == nullptr) {
    return FALSE;
  }
  cairo_rectangle(cr, 0, 0, g_logical, g_logical);
  cairo_clip(cr);
  cairo_set_source_surface(cr, g_surface, 0,
                           -static_cast<double>(g_pose.frame) * g_logical);
  cairo_paint_with_alpha(cr, g_pose.alpha / 255.0);
  return FALSE;
}

// click-through: אזור קלט ריק כך שלחיצות עוברות דרך החלון.
void OnRealize(GtkWidget* widget, gpointer) {
  GdkWindow* gdk_window = gtk_widget_get_window(widget);
  if (gdk_window != nullptr) {
    cairo_region_t* empty = cairo_region_create();
    gdk_window_input_shape_combine_region(gdk_window, empty, 0, 0);
    cairo_region_destroy(empty);
  }
}

tl::Pose PoseNow(gint64 now_us) {
  const double t = (now_us - g_shown_at_us) / 1000.0;
  if (g_closing) {
    return {g_close_from.frame,
            tl::FadeOutAlpha(g_close_from.alpha,
                             (now_us - g_close_at_us) / 1000.0)};
  }
  if (t < tl::kFadeInMs) return {0, tl::FadeInAlpha(t)};
  return tl::PoseAt(t - tl::kFadeInMs, g_frames, g_animate);
}

// טיק לפי שעון הפריימים של GTK. מבקש ציור רק כשהפריים או האטימות השתנו.
gboolean Tick(GtkWidget* widget, GdkFrameClock*, gpointer) {
  const gint64 now = g_get_monotonic_time();
  if (!g_closing && g_close_requested &&
      now - g_shown_at_us >= kMinDisplayUs) {
    g_closing = true;
    g_close_at_us = now;
    g_close_from = g_pose;
  }
  const tl::Pose pose = PoseNow(now);
  if (g_closing && pose.alpha <= 0) {
    g_tick_id = 0;
    g_idle_add(DestroyOnIdle, nullptr);
    return G_SOURCE_REMOVE;
  }
  if (pose.frame != g_pose.frame ||
      static_cast<int>(pose.alpha + 0.5) !=
          static_cast<int>(g_pose.alpha + 0.5)) {
    g_pose = pose;
    gtk_widget_queue_draw(widget);
  }
  // סמל סטטי שסיים להופיע: אין מה לצייר עד הסגירה, ולכן לא מחזיקים את השעון.
  const double t = (now - g_shown_at_us) / 1000.0;
  if (!g_closing && !g_close_requested && !g_animate &&
      t >= tl::kFadeInMs) {
    g_tick_id = 0;
    return G_SOURCE_REMOVE;
  }
  return G_SOURCE_CONTINUE;
}

void ShowWindow(cairo_surface_t* surface, int frames, int logical) {
  g_surface = surface;
  g_frames = frames;
  g_logical = logical;
  // מקדם הקנה של המשטח: הציור כולו ביחידות לוגיות, חד גם ב-HiDPI.
  const double surface_scale =
      static_cast<double>(cairo_image_surface_get_width(surface)) / logical;
  cairo_surface_set_device_scale(surface, surface_scale, surface_scale);

  GtkWidget* win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
  gtk_window_set_resizable(GTK_WINDOW(win), FALSE);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(win), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(win), TRUE);
  gtk_window_set_keep_above(GTK_WINDOW(win), TRUE);
  gtk_window_set_accept_focus(GTK_WINDOW(win), FALSE);
  gtk_window_set_focus_on_map(GTK_WINDOW(win), FALSE);
  gtk_window_set_type_hint(GTK_WINDOW(win), GDK_WINDOW_TYPE_HINT_SPLASHSCREEN);
  gtk_window_set_position(GTK_WINDOW(win), GTK_WIN_POS_CENTER);
  gtk_window_set_default_size(GTK_WINDOW(win), logical, logical);
  gtk_widget_set_app_paintable(win, TRUE);

  // visual עם ערוץ אלפא לשקיפות (דורש compositor).
  GdkScreen* screen = gtk_widget_get_screen(win);
  GdkVisual* rgba = gdk_screen_get_rgba_visual(screen);
  if (rgba != nullptr) {
    gtk_widget_set_visual(win, rgba);
  }

  g_signal_connect(win, "draw", G_CALLBACK(OnDraw), nullptr);
  g_signal_connect(win, "realize", G_CALLBACK(OnRealize), nullptr);

  g_pose = {0, 0};
  g_closing = false;
  g_splash = win;
  gtk_widget_show_all(win);
  g_shown_at_us = g_get_monotonic_time();
  g_tick_id = gtk_widget_add_tick_callback(win, Tick, nullptr, nullptr);
}

void OnLoaded(GObject*, GAsyncResult* result, gpointer) {
  const LoadRequest* req = static_cast<const LoadRequest*>(
      g_task_get_task_data(G_TASK(result)));
  const bool strip = req->strip;
  const int scale = req->scale;
  GError* error = nullptr;
  Loaded* loaded = static_cast<Loaded*>(
      g_task_propagate_pointer(G_TASK(result), &error));
  if (error != nullptr) g_error_free(error);

  if (loaded == nullptr) {
    // רצועה פגומה או חסרה: הסמל הסטטי, כמו בהפחתת תנועה.
    if (strip && !g_close_requested) {
      StartLoad(/*strip=*/false, scale);
    } else {
      g_loading = false;
    }
    return;
  }
  g_loading = false;
  // החלון הראשי כבר נחשף — אין טעם להציג splash.
  if (g_close_requested) {
    FreeLoaded(loaded);
    return;
  }
  g_animate = strip;
  cairo_surface_t* surface = loaded->surface;
  loaded->surface = nullptr;
  ShowWindow(surface, loaded->frames, strip ? kFrameSize : kIconSize);
  FreeLoaded(loaded);
}

void StartLoad(bool strip, int scale) {
  const std::string dir = ExecutableDir();
  LoadRequest* req = new LoadRequest;
  req->strip = strip;
  req->scale = scale;
  req->size = kIconSize * scale;
  req->path = strip ? dir + (scale >= 2 ? "/data/splash/splash_book_200.png"
                                        : "/data/splash/splash_book_100.png")
                    : dir + "/data/flutter_assets/assets/icon/iconnew.png";
  g_loading = true;
  GTask* task = g_task_new(nullptr, nullptr, OnLoaded, nullptr);
  g_task_set_task_data(task, req, FreeRequest);
  g_task_run_in_thread(task, LoadInThread);
  g_object_unref(task);
}

int MonitorScale() {
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor =
      display != nullptr ? gdk_display_get_primary_monitor(display) : nullptr;
  if (monitor == nullptr && display != nullptr) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  const int scale =
      monitor != nullptr ? gdk_monitor_get_scale_factor(monitor) : 1;
  return scale > 0 ? scale : 1;
}

}  // namespace

void splash_window_show() {
  if (g_splash != nullptr || g_loading) {
    return;
  }
  g_close_requested = false;
  StartLoad(/*strip=*/AnimationsEnabled(), MonitorScale());
}

void splash_window_close() {
  // מסמן בקשת סגירה; הטיק עובר ל-fade-out אחרי זמן התצוגה המינימלי.
  g_close_requested = true;
  if (g_splash != nullptr && g_tick_id == 0) {
    g_tick_id = gtk_widget_add_tick_callback(g_splash, Tick, nullptr, nullptr);
  }
}
