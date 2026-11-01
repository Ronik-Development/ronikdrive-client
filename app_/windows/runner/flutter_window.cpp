#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::SetShowOnStart(bool show_on_start) {
  show_on_start_ = show_on_start;
}

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
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "ronikcloud/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto hwnd = GetHandle();
    const auto& method = call.method_name();
    if (method == "configure") {
      // Resize outside the active Dart platform-channel callback.
      PostMessage(hwnd, WM_APP + 0x310, 0, 0);
    } else if (method == "minimize") {
      PostMessage(hwnd, WM_SYSCOMMAND, SC_MINIMIZE, 0);
    } else if (method == "maximize") {
      PostMessage(hwnd, WM_SYSCOMMAND, IsZoomed(hwnd) ? SC_RESTORE : SC_MAXIMIZE, 0);
    } else if (method == "close") {
      PostMessage(hwnd, WM_CLOSE, 0, 0);
    } else if (method == "drag") {
      ReleaseCapture();
      PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, GetMessagePos());
    } else {
      result->NotImplemented();
      return;
    }
    result->Success();
  });
  desktop_drive_ = std::make_unique<DesktopDrive>(flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (show_on_start_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_.reset();
  desktop_drive_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_NCCALCSIZE && wparam != 0) {
    // Draw Flutter to the edge; retain resizing through hit testing below
    // instead of exposing an empty native frame around the content.
    return 0;
  }
  if (message == WM_NCHITTEST && !IsZoomed(hwnd)) {
    RECT rect;
    if (GetWindowRect(hwnd, &rect)) {
      const int x = static_cast<short>(LOWORD(lparam));
      const int y = static_cast<short>(HIWORD(lparam));
      const int border = MulDiv(6, GetDpiForWindow(hwnd), 96);
      const bool left = x < rect.left + border;
      const bool right = x >= rect.right - border;
      const bool top = y < rect.top + border;
      const bool bottom = y >= rect.bottom - border;
      if (top && left) return HTTOPLEFT;
      if (top && right) return HTTOPRIGHT;
      if (bottom && left) return HTBOTTOMLEFT;
      if (bottom && right) return HTBOTTOMRIGHT;
      if (left) return HTLEFT;
      if (right) return HTRIGHT;
      if (top) return HTTOP;
      if (bottom) return HTBOTTOM;
    }
  }
  if (message == WM_GETMINMAXINFO) {
    // Captionless windows must explicitly maximize to the work area rather
    // than the monitor bounds, which include the Windows taskbar.
    MONITORINFO monitor_info{sizeof(MONITORINFO)};
    if (GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                       &monitor_info)) {
      auto limits = reinterpret_cast<MINMAXINFO*>(lparam);
      const RECT work = monitor_info.rcWork;
      const RECT monitor = monitor_info.rcMonitor;
      limits->ptMaxPosition.x = work.left - monitor.left;
      limits->ptMaxPosition.y = work.top - monitor.top;
      limits->ptMaxSize.x = work.right - work.left;
      limits->ptMaxSize.y = work.bottom - work.top;
      return 0;
    }
  }
  if (message == WM_APP + 0x310) {
    // Retain resize borders, taskbar identity and system keyboard shortcuts.
    SetWindowLongPtr(hwnd, GWL_STYLE, GetWindowLongPtr(hwnd, GWL_STYLE) & ~WS_CAPTION);
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
    return 0;
  }
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
