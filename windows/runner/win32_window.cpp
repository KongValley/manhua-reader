#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <algorithm>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

constexpr wchar_t kWindowPlacementKey[] = L"Software\\ManhuaReader";
constexpr wchar_t kWindowPlacementValue[] = L"WindowPlacement";

struct SavedPlacement {
  RECT bounds;
  DWORD maximized;
};

// Store normal bounds in screen coordinates, including on secondary displays.
// 用屏幕坐标保存窗口的普通尺寸和位置，包括在副显示器上时。
void SavePlacement(HWND window) {
  WINDOWPLACEMENT placement = {sizeof(placement)};
  if (!GetWindowPlacement(window, &placement)) return;
  // rcNormalPosition is already in virtual-screen coordinates. Converting it
  // by the work-area offset would shift the window on every launch whenever
  // the taskbar sits on the top or left edge.
  // rcNormalPosition 已经是虚拟屏幕坐标；再按工作区偏移换算，会在任务栏
  // 位于顶部或左侧时让窗口每次启动都平移一段。
  SavedPlacement saved = {placement.rcNormalPosition, 0};
  saved.maximized = placement.showCmd == SW_SHOWMAXIMIZED ||
                     (placement.flags & WPF_RESTORETOMAXIMIZED) != 0;
  RegSetKeyValueW(HKEY_CURRENT_USER, kWindowPlacementKey, kWindowPlacementValue,
                   REG_BINARY, &saved, sizeof(saved));
}

SavedPlacement StartupPlacement(const Win32Window::Size& size,
                                bool remember_placement) {
  SavedPlacement saved = {};
  HMONITOR monitor = nullptr;
  if (remember_placement) {
    DWORD bytes = sizeof(saved);
    if (RegGetValueW(HKEY_CURRENT_USER, kWindowPlacementKey,
                     kWindowPlacementValue, RRF_RT_REG_BINARY, nullptr,
                     &saved, &bytes) == ERROR_SUCCESS &&
        bytes == sizeof(saved) && saved.bounds.right > saved.bounds.left &&
        saved.bounds.bottom > saved.bounds.top) {
      monitor = MonitorFromRect(&saved.bounds, MONITOR_DEFAULTTONULL);
    }
  }

  const bool restoring = monitor != nullptr;
  if (!restoring) {
    POINT cursor = {};
    GetCursorPos(&cursor);
    monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY);
    saved.maximized = 0;
  }
  MONITORINFO info = {sizeof(info)};
  if (!GetMonitorInfoW(monitor, &info)) {
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &info.rcWork, 0);
  }
  const RECT& work = info.rcWork;
  const LONG work_width = work.right - work.left;
  const LONG work_height = work.bottom - work.top;
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const LONG width = std::min(work_width, restoring
      ? saved.bounds.right - saved.bounds.left
      : static_cast<LONG>(MulDiv(size.width, dpi, 96)));
  const LONG height = std::min(work_height, restoring
      ? saved.bounds.bottom - saved.bounds.top
      : static_cast<LONG>(MulDiv(size.height, dpi, 96)));
  const LONG left = restoring
      ? std::clamp(saved.bounds.left, work.left, work.right - width)
      : work.left + (work_width - width) / 2;
  const LONG top = restoring
      ? std::clamp(saved.bounds.top, work.top, work.bottom - height)
      : work.top + (work_height - height) / 2;
  saved.bounds = {left, top, left + width, top + height};
  return saved;
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = Win32Window::kClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return Win32Window::kClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(Win32Window::kClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title, const Size& size,
                         bool remember_placement) {
  Destroy();
  remember_placement_ = remember_placement;
  const auto placement = StartupPlacement(size, remember_placement);
  show_command_ = placement.maximized ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;
  const RECT& bounds = placement.bounds;

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();
  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW, bounds.left, bounds.top,
      bounds.right - bounds.left, bounds.bottom - bounds.top, nullptr, nullptr,
      GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, show_command_);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE:
      if (remember_placement_) SavePlacement(hwnd);
      break;

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
