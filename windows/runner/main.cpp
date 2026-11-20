#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdlib>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);

  // Optional initial window size, handy for screenshots and small-screen
  // verification. Production launches without these variables keep the
  // default size.
  auto read_env_size = [](const wchar_t* name, unsigned int fallback) {
    wchar_t buffer[32];
    const DWORD length = ::GetEnvironmentVariableW(name, buffer, 32);
    if (length == 0 || length >= 32) return fallback;
    const long value = wcstol(buffer, nullptr, 10);
    if (value < 320 || value > 4000) return fallback;
    return static_cast<unsigned int>(value);
  };
  size = Win32Window::Size(
      read_env_size(L"MANHUA_WINDOW_WIDTH", size.width),
      read_env_size(L"MANHUA_WINDOW_HEIGHT", size.height));

  if (!window.Create(L"\u6F2B\u9605", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
