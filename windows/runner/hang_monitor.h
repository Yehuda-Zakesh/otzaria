#ifndef RUNNER_HANG_MONITOR_H_
#define RUNNER_HANG_MONITOR_H_

#include <windows.h>

// גלאי תקיעה בזמן ריצה: thread צדדי בודק פעם בשנייה את IsHungAppWindow של
// החלון הראשי, וכותב ל-errors.txt את מחסנית ה-thread הראשי כשהוא נתקע.
namespace hang_monitor {

// נשלחת לחלון הראשי כשהתקיעה הסתיימה. LPARAM = משך התקיעה במילישניות.
constexpr UINT kMsgAppHangRecovered = WM_APP + 0x104;

// רושם את החלון הראשי. יש לקרוא מה-thread הראשי, לא בהפעלת CLI.
void SetMainWindow(HWND window);

// מתחיל את הניטור אם נרשם חלון ראשי. אידמפוטנטי; נקרא בחשיפת החלון.
void Start();

// עוצר וממתין ל-watcher. בטוח לקריאה חוזרת; לפני startup_watchdog::Stop.
void Stop();

}  // namespace hang_monitor

#endif  // RUNNER_HANG_MONITOR_H_
