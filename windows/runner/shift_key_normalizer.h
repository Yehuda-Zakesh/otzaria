#ifndef RUNNER_SHIFT_KEY_NORMALIZER_H_
#define RUNNER_SHIFT_KEY_NORMALIZER_H_

#include <windows.h>

// מתקן הודעות Shift עם דגל extended או scancode חריג לפני שה-engine רואה אותן.
// ה-engine רושם אותן כמקש פיזי לא מוכר שאינו משתחרר, ולחיצה מרחיבה בחירה (#1645).
// TODO: למחוק כשה-engine יתקן את flutter/flutter#181907.
void InstallShiftKeyNormalizer(HWND flutter_view);

#endif  // RUNNER_SHIFT_KEY_NORMALIZER_H_
