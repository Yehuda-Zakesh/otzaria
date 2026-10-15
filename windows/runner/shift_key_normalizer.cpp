#include "shift_key_normalizer.h"

#include <commctrl.h>

namespace {

constexpr UINT_PTR kSubclassId = 0x1645;
constexpr UINT kScanCodeShiftLeft = 0x2A;
constexpr UINT kScanCodeShiftRight = 0x36;
constexpr LPARAM kScanCodeMask = 0x00FF0000;
constexpr LPARAM kExtendedBit = 0x01000000;

LRESULT CALLBACK NormalizerProc(HWND hwnd,
                                UINT message,
                                WPARAM wparam,
                                LPARAM lparam,
                                UINT_PTR,
                                DWORD_PTR) {
  switch (message) {
    case WM_KEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYDOWN:
    case WM_SYSKEYUP:
      if (wparam == VK_SHIFT) {
        // כל צד מקבל את ה-scancode התקני שלו; כך סנכרון ה-modifiers של ה-engine
        // בתזוזת עכבר מרפא גם Shift שהשחרור שלו אבד.
        const UINT scancode = (lparam & kScanCodeMask) >> 16;
        const UINT normalized = scancode == kScanCodeShiftRight
                                    ? kScanCodeShiftRight
                                    : kScanCodeShiftLeft;
        lparam = (lparam & ~(kScanCodeMask | kExtendedBit)) |
                 (static_cast<LPARAM>(normalized) << 16);
      }
      break;
    case WM_NCDESTROY:
      RemoveWindowSubclass(hwnd, NormalizerProc, kSubclassId);
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

void InstallShiftKeyNormalizer(HWND flutter_view) {
  SetWindowSubclass(flutter_view, NormalizerProc, kSubclassId, 0);
}
