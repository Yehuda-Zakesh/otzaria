#include <stdlib.h>

typedef struct {
  int x, y, width, height, default_width, default_height, scale, state, visible;
  void* normal;
  void (*free_normal)(void*);
} TestWindow;

void* test_window_new(int state) {
  TestWindow* w = calloc(1, sizeof(TestWindow));
  *w = (TestWindow){.x = 100, .y = 50, .width = 800, .height = 600,
                    .default_width = state ? 900 : 800, .default_height = state ? 650 : 600,
                    .scale = 1, .state = state};
  return w;
}
void test_window_state(TestWindow* w, int state) {
  w->state = state;
  w->width = 1920;
  w->height = 1080;
}
void test_window_free(TestWindow* w) {
  if (w->normal) w->free_normal(w->normal);
  free(w);
}
void gtk_window_get_position(TestWindow* w, int* x, int* y) { *x = w->x; *y = w->y; }
void gtk_window_get_size(TestWindow* w, int* x, int* y) { *x = w->width; *y = w->height; }
void gtk_window_get_default_size(TestWindow* w, int* x, int* y) { *x = w->default_width; *y = w->default_height; }
int gtk_widget_get_scale_factor(TestWindow* w) { return w->scale; }
void* gtk_widget_get_window(TestWindow* w) { return w; }
int gdk_window_get_state(TestWindow* w) { return w->state; }
void* g_object_get_data(TestWindow* w, const char* key) { (void)key; return w->normal; }
void g_object_set_data_full(TestWindow* w, const char* key, void* value, void (*destroy)(void*)) {
  (void)key;
  if (w->normal) w->free_normal(w->normal);
  w->normal = value;
  w->free_normal = destroy;
}
void g_free(void* value) { free(value); }
void gtk_window_move(TestWindow* w, int x, int y) { w->x = x; w->y = y; }
void gtk_window_resize(TestWindow* w, int width, int height) { w->width = width; w->height = height; }
int gtk_widget_get_visible(TestWindow* w) { return w->visible; }
void gtk_widget_show(TestWindow* w) { w->visible = 1; }
