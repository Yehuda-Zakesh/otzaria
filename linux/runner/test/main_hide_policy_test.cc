#include <cassert>

#include "../main_hide_policy.h"

int main() {
  assert(ShouldExitOnWindowHide(0, false));
  // חלון Dart גלוי שומר על התהליך גם כשכל חלונות ה-runner מוסתרים.
  assert(!ShouldExitOnWindowHide(0, true));
  assert(!ShouldExitOnWindowHide(1, false));
  assert(!ShouldExitOnWindowHide(2, true));
  return 0;
}
