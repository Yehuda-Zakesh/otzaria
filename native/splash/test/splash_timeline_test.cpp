// טסט עצמאי לציר הזמן של ה-splash.
// הרצה: native/splash/test/run_splash_timeline_test.sh, או ה-ps1 שלצדו ב-Windows.
#include "../splash_timeline.h"

#include <cmath>
#include <cstdio>

namespace tl = splash_timeline;

static int failures = 0;

static void Expect(bool ok, const char* what) {
  if (!ok) {
    std::printf("FAIL: %s\n", what);
    ++failures;
  }
}

static bool Near(double a, double b) { return std::fabs(a - b) < 1e-6; }

int main() {
  const int frames = 24;

  // פתיחה: פריים לפי הזמן, 24 לשנייה, באטימות מלאה.
  Expect(tl::PoseAt(0, frames, true).frame == 0, "starts closed");
  Expect(tl::PoseAt(tl::kFrameMs * 5 + 1, frames, true).frame == 5,
         "frame follows time");
  Expect(Near(tl::PoseAt(500, frames, true).alpha, tl::kAlpha),
         "full opacity while opening");
  Expect(tl::PoseAt(tl::LandedAtMs(frames), frames, true).frame == 23,
         "lands open on the last frame");
  Expect(tl::PoseAt(60000, frames, true).frame == 23, "stays open");

  // עלייה איטית: אחרי ההמתנה הספר "נושם" בגבולות העומק, ומתחיל ברצף.
  const double breath = tl::LandedAtMs(frames) + tl::kBreathDelayMs;
  Expect(Near(tl::PoseAt(breath, frames, true).alpha, tl::kAlpha),
         "breath starts at full opacity");
  const double lowest =
      tl::PoseAt(breath + tl::kBreathPeriodMs / 2, frames, true).alpha;
  Expect(Near(lowest, tl::kAlpha * (1 - tl::kBreathDepth)),
         "breath reaches its depth at half period");
  bool in_range = true;
  for (double t = breath; t < breath + 3 * tl::kBreathPeriodMs; t += 7) {
    const double a = tl::PoseAt(t, frames, true).alpha;
    in_range &= a <= tl::kAlpha + 1e-9 &&
                a >= tl::kAlpha * (1 - tl::kBreathDepth) - 1e-9;
  }
  Expect(in_range, "breath stays within its depth");

  // הפחתת תנועה / פריים יחיד: אין שום שינוי לאורך זמן.
  const double times[] = {0.0, 500.0, 5000.0, 60000.0};
  for (double t : times) {
    const tl::Pose p = tl::PoseAt(t, frames, false);
    Expect(p.frame == 0 && Near(p.alpha, tl::kAlpha), "reduced motion static");
    Expect(tl::PoseAt(t, 1, true).frame == 0, "single frame is static");
  }
  Expect(tl::NextChangeMs(1000, frames, false) < 0,
         "reduced motion never schedules a change");

  // פענוח איטי משהה את הניגון על הפריים האחרון שפוענח.
  Expect(tl::PoseAt(tl::ClampPlayMs(900, 3, frames), frames, true).frame == 2,
         "playback waits for decoding");
  Expect(Near(tl::ClampPlayMs(900, frames, frames), 900),
         "no clamp once all decoded");

  // תזמון: גבול הפריים הבא, ואז תחילת הנשימה.
  Expect(Near(tl::NextChangeMs(10, frames, true), tl::kFrameMs),
         "next frame boundary");
  Expect(Near(tl::NextChangeMs(tl::LandedAtMs(frames) + 1, frames, true),
              breath),
         "hold until breath");

  // fade-in ו-fade-out מוגבלים ומסתיימים.
  Expect(Near(tl::FadeInAlpha(0), 0) &&
             Near(tl::FadeInAlpha(tl::kFadeInMs * 2), tl::kAlpha),
         "fade-in bounds");
  Expect(Near(tl::FadeOutAlpha(150, 0), 150) &&
             Near(tl::FadeOutAlpha(150, tl::kFadeOutMs), 0),
         "fade-out ends at zero");

  if (failures == 0) std::printf("splash_timeline: all tests passed\n");
  return failures == 0 ? 0 : 1;
}
