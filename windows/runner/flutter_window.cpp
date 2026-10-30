#include "flutter_window.h"

#include <commctrl.h>
#include <imm.h>
#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

LRESULT CALLBACK HandleMouseInput(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam, UINT_PTR subclass_id,
                                  DWORD_PTR) {
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, HandleMouseInput, subclass_id);
  }

  // Match the engine's exclusion of mouse messages promoted from touch or pen.
  constexpr LPARAM kTouchOrPenSignature = 0xFF515700;
  constexpr LPARAM kSignatureMask = 0xFFFFFF00;
  if (message < WM_MOUSEFIRST || message > WM_MOUSELAST ||
      (GetMessageExtraInfo() & kSignatureMask) == kTouchOrPenSignature) {
    return DefSubclassProc(hwnd, message, wparam, lparam);
  }

  constexpr WPARAM kMouseButtons =
      MK_LBUTTON | MK_RBUTTON | MK_MBUTTON | MK_XBUTTON1 | MK_XBUTTON2;
  switch (message) {
    case WM_MOUSEMOVE:
      // Backport https://github.com/flutter/flutter/pull/190029 at the runner.
      if ((wparam & kMouseButtons) != 0 && GetCapture() != hwnd) {
        return 0;
      }
      break;
    case WM_LBUTTONDOWN:
    case WM_RBUTTONDOWN:
    case WM_MBUTTONDOWN:
    case WM_XBUTTONDOWN:
      SetCapture(hwnd);
      break;
    case WM_LBUTTONUP:
    case WM_RBUTTONUP:
    case WM_MBUTTONUP:
    case WM_XBUTTONUP: {
      const bool keep_capture =
          (wparam & kMouseButtons) != 0 && GetCapture() == hwnd;
      if ((wparam & kMouseButtons) == 0) {
        ReleaseCapture();
      }
      const auto result = DefSubclassProc(hwnd, message, wparam, lparam);
      // Flutter 3.47 releases capture on every left-button up. Keep it while
      // another button is still held, as master does, without stealing it back.
      if (message == WM_LBUTTONUP && keep_capture && GetCapture() == nullptr) {
        SetCapture(hwnd);
      }
      return result;
    }
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  const HWND flutter_view = flutter_controller_->view()->GetNativeWindow();
  SetWindowSubclass(flutter_view, HandleMouseInput, 0, 0);
  SetChildContent(flutter_view);
  ImmAssociateContextEx(flutter_view, nullptr, 0);

  ime_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "piliplus/windows_ime",
          &flutter::StandardMethodCodec::GetInstance());
  ime_channel_->SetMethodCallHandler(
      [flutter_view](const auto& call, auto result) {
        if (call.method_name() != "setImeEnabled") {
          result->NotImplemented();
          return;
        }

        const auto* enabled = std::get_if<bool>(call.arguments());
        if (enabled == nullptr) {
          result->Error("invalid_argument", "Expected a boolean value.");
          return;
        }

        ImmAssociateContextEx(flutter_view, nullptr,
                              *enabled ? IACE_DEFAULT : 0);
        result->Success();
      });

  // flutter_controller_->engine()->SetNextFrameCallback([&]() {
  //   this->Show();
  // });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
