#ifndef RUNNER_SPLASH_TIMELINE_H_
#define RUNNER_SPLASH_TIMELINE_H_

#include <cmath>

// ציר הזמן של אנימציית ה-splash כפונקציות טהורות (ללא Win32), כדי שייבדק בטסט.
// הספר נפתח פעם אחת, נח פתוח, ובעלייה איטית "נושם" (גל אטימות רדוד) עד הסגירה.
namespace splash_timeline {

constexpr double kPi = 3.14159265358979323846;

constexpr double kFramesPerSecond = 24.0;
constexpr double kFrameMs = 1000.0 / kFramesPerSecond;
constexpr double kAlpha = 178.0;  // ~70%, כמו הסמל הסטטי
constexpr double kFadeInMs = 195.0;
constexpr double kFadeOutMs = 90.0;
constexpr double kBreathDelayMs = 800.0;  // מרגע שהספר נחת פתוח
constexpr double kBreathPeriodMs = 2800.0;
constexpr double kBreathDepth = 0.22;

struct Pose {
  int frame;
  double alpha;  // 0..255
};

inline double Clamp01(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

inline double FadeInAlpha(double elapsed_ms) {
  return kAlpha * Clamp01(elapsed_ms / kFadeInMs);
}

// 0 = הדעיכה הסתיימה.
inline double FadeOutAlpha(double from_alpha, double elapsed_ms) {
  return from_alpha * (1.0 - Clamp01(elapsed_ms / kFadeOutMs));
}

inline double LandedAtMs(int frames) {
  return frames > 1 ? (frames - 1) * kFrameMs : 0.0;
}

// animate=false (הפחתת תנועה, או פריים יחיד) — פריים 0 קבוע באטימות מלאה.
inline Pose PoseAt(double play_ms, int frames, bool animate) {
  if (!animate || frames <= 1) return {0, kAlpha};
  if (play_ms < 0) play_ms = 0;
  int frame = static_cast<int>(play_ms / kFrameMs);
  if (frame > frames - 1) frame = frames - 1;
  const double breath_ms = play_ms - LandedAtMs(frames) - kBreathDelayMs;
  double alpha = kAlpha;
  if (breath_ms > 0) {
    // מתחיל באטימות מלאה ובשיפוע אפס — המעבר מהעמידה לגל רציף.
    const double wave =
        (1.0 - std::cos(2.0 * kPi * breath_ms / kBreathPeriodMs)) / 2.0;
    alpha = kAlpha * (1.0 - kBreathDepth * wave);
  }
  return {frame, alpha};
}

// הניגון לא עובר את הפריים האחרון שפוענח: פענוח איטי משהה את הספר ולא מדלג.
inline double ClampPlayMs(double play_ms, int decoded, int frames) {
  if (decoded >= frames || decoded <= 0) return play_ms;
  const double limit = decoded * kFrameMs - 0.001;
  return play_ms < limit ? play_ms : limit;
}

// מתי התמונה משתנה בפעם הבאה (מתחילת הניגון); -1 = לא עד הסגירה.
inline double NextChangeMs(double play_ms, int frames, bool animate) {
  if (!animate || frames <= 1) return -1;
  const double landed = LandedAtMs(frames);
  if (play_ms < landed) {
    return (static_cast<int>(play_ms / kFrameMs) + 1) * kFrameMs;
  }
  const double breath_start = landed + kBreathDelayMs;
  if (play_ms < breath_start) return breath_start;
  return play_ms + 33.0;  // ~30 עדכוני אטימות בשנייה
}

}  // namespace splash_timeline

#endif  // RUNNER_SPLASH_TIMELINE_H_
