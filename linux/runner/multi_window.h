#ifndef RUNNER_MULTI_WINDOW_H_
#define RUNNER_MULTI_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

// ריבוי חלונות ב-Linux: חלונות נוספים הם חלונות Dart (RegularWindowController)
// במנוע הראשי. ה-runner מחזיק רק את החלון הראשי: הסתרה, הבאה לחזית ושחזור,
// וה-`GtkWindow*` שלו לחלונות Dart (ערוץ `otzaria/multiwindow`).
//
// הגרירה בין חלונות (`dragOutToSystem` ואחיותיה) אינה ממומשת כאן ומחזירה
// not-implemented: Wayland אינו מאפשר מיקום חלון או קריאת מיקום הסמן מחוץ
// לחלון.

// רושם את החלון הראשי ומתקין על המנוע שלו את ערוץ `otzaria/multiwindow`.
// נקרא פעם אחת מ-`my_application_activate`.
void otzaria_multi_window_register_main(GtkWindow* window, FlView* view);

// מחיל את סרגל הכותרת של אוצריא: header bar ב-GNOME, כותרת מסורתית
// בשאר מנהלי החלונות ב-X11.
void otzaria_apply_window_titlebar(GtkWindow* window);

G_END_DECLS

#endif  // RUNNER_MULTI_WINDOW_H_
