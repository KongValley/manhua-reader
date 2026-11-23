#include <flutter/dart_project.h>
#include <windows.h>

#include <cstdlib>
#include <filesystem>
#include <memory>
#include <optional>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kInstanceMutex[] = L"Local\\ManhuaReader.MainInstance";

bool ForwardLaunch(const std::vector<std::wstring>& files) {
  // A launch can arrive before the first process has created its window.
  // 第二次启动可能发生在第一个进程创建窗口之前。
  HWND target = nullptr;
  for (int attempt = 0; attempt < 100 && !target; ++attempt) {
    target = FindWindowW(Win32Window::kClassName, nullptr);
    if (!target) Sleep(50);
  }
  if (!target) return false;

  DWORD pid = 0;
  GetWindowThreadProcessId(target, &pid);
  if (pid) AllowSetForegroundWindow(pid);

  auto send = [target](const std::wstring& path) {
    COPYDATASTRUCT data = {
        FlutterWindow::kOpenFileMessage,
        static_cast<DWORD>(path.size() * sizeof(wchar_t)),
        const_cast<wchar_t*>(path.data()),
    };
    DWORD_PTR accepted = 0;
    return SendMessageTimeoutW(target, WM_COPYDATA, 0,
                               reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG,
                               5000, &accepted) != 0 && accepted != 0;
  };
  if (files.empty()) return send(L"");
  bool delivered = true;
  for (const auto& file : files) {
    if (!send(file)) delivered = false;
  }
  return delivered;
}

std::optional<unsigned int> ReadWindowSizeOverride(const wchar_t* name) {
  wchar_t buffer[32];
  const DWORD length = GetEnvironmentVariableW(name, buffer, 32);
  if (length == 0 || length >= 32) return std::nullopt;
  wchar_t* end = nullptr;
  const long value = wcstol(buffer, &end, 10);
  if (*end != L'\0' || value < 320 || value > 4000) return std::nullopt;
  return static_cast<unsigned int>(value);
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const auto files = GetOpenFileArguments();
  const auto mutex = CreateMutexW(nullptr, FALSE, kInstanceMutex);
  const DWORD mutex_status = GetLastError();
  std::unique_ptr<void, decltype(&CloseHandle)> instance_handle(mutex,
                                                              CloseHandle);
  if (!mutex) return EXIT_FAILURE;
  if (mutex_status == ERROR_ALREADY_EXISTS) {
    if (ForwardLaunch(files)) return EXIT_SUCCESS;
    // Release this handle before blocking on the error box; otherwise the
    // dialog keeps the named mutex alive and later launches queue behind it.
    // 在弹出错误框前释放句柄；否则对话框会让命名互斥量继续存在，
    // 之后的启动都会被它挡住。
    instance_handle.reset();
    MessageBoxW(nullptr, L"\u65E0\u6CD5\u8054\u7CFB\u5DF2\u6253\u5F00\u7684\u6F2B\u9605\u7A97\u53E3\u3002",
                L"\u6F2B\u9605", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  const HRESULT com_status = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const auto data_path = std::filesystem::path(GetExecutablePath()).parent_path() / L"data";
  flutter::DartProject project(data_path.wstring());
  project.set_dart_entrypoint_arguments(GetCommandLineArguments());
  const auto width = ReadWindowSizeOverride(L"MANHUA_WINDOW_WIDTH");
  const auto height = ReadWindowSizeOverride(L"MANHUA_WINDOW_HEIGHT");
  const Win32Window::Size size(width.value_or(1280), height.value_or(800));

  int exit_code = EXIT_FAILURE;
  {
    FlutterWindow window(project, files);
    if (window.Create(L"\u6F2B\u9605", size, !width && !height)) {
      window.SetQuitOnClose(true);
      MSG msg;
      BOOL status;
      while ((status = GetMessageW(&msg, nullptr, 0, 0)) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
      }
      if (status == 0) exit_code = EXIT_SUCCESS;
    }
  }
  if (SUCCEEDED(com_status)) CoUninitialize();
  return exit_code;
}
