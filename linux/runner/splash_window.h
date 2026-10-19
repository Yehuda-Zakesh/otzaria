#ifndef RUNNER_SPLASH_WINDOW_H_
#define RUNNER_SPLASH_WINDOW_H_

#include <gtk/gtk.h>

G_BEGIN_DECLS

// חלון splash נייטיב (GTK): חלון שקוף, ללא-מסגרת, keep-above, click-through,
// ממורכז על המסך, שבו הספר המוזהב נפתח (ציר הזמן ב-native/splash, משותף
// ל-Windows). עם הפחתת תנועה — הסמל הסטטי. נפרד מחלון ה-Flutter הראשי.
//
// הערה: שקיפות דורשת compositor (קיים ברוב שולחנות העבודה; בלי זה הרקע ייראה
// אטום). הפענוח ב-thread של GTask; הציור לפי שעון הפריימים של GTK.

// מתחיל לטעון את הפריימים ברקע; החלון מופיע (fade-in) כשהם מוכנים.
// נקרא פעם אחת בעליית האפליקציה. בכשל טעינה — ללא splash.
void splash_window_show();

// מתחיל את אנימציית ה-fade-out; בסיומה החלון נהרס. אידמפוטנטי. נקרא דרך
// ה-method channel "otzaria/splash" בעת חשיפת החלון הראשי.
void splash_window_close();

G_END_DECLS

#endif  // RUNNER_SPLASH_WINDOW_H_
