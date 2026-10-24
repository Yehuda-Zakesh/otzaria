#ifndef RUNNER_MAIN_HIDE_POLICY_H_
#define RUNNER_MAIN_HIDE_POLICY_H_

// הסתרת חלון של ה-runner מסיימת את התהליך רק כשלא נשאר שום חלון גלוי:
// לא של ה-runner ולא חלון Dart (ריבוי תצוגות), שאינו נספר ברשימת ה-runner.
inline bool ShouldExitOnWindowHide(int live_runner_windows,
                                   bool has_visible_dart_view) {
  return live_runner_windows == 0 && !has_visible_dart_view;
}

#endif  // RUNNER_MAIN_HIDE_POLICY_H_
