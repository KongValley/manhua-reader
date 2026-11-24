#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <filesystem>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "pdf_password_store.h"
#include "utils.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             const std::vector<std::wstring>& launch_files)
    : project_(project), pending_files_(launch_files.begin(), launch_files.end()) {}

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
  RegisterPdfPasswordStore(flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  ConfigureExternalOpen();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::ConfigureExternalOpen() {
  external_open_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "manhua/external_open",
          &flutter::StandardMethodCodec::GetInstance());
  external_open_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "takeNext") {
      if (pending_files_.empty()) {
        result->Success();
        return;
      }
      const auto& path = pending_files_.front();
      const auto name = std::filesystem::path(path).filename().wstring();
      const flutter::EncodableMap request = {
          {flutter::EncodableValue("name"),
           flutter::EncodableValue(Utf8FromUtf16(name.c_str()))},
          {flutter::EncodableValue("path"),
           flutter::EncodableValue(Utf8FromUtf16(path.c_str()))},
      };
      pending_files_.pop_front();
      result->Success(flutter::EncodableValue(request));
    } else if (call.method_name() == "associationsRegistered") {
      result->Success(flutter::EncodableValue(AreFileAssociationsRegistered()));
    } else if (call.method_name() == "setAssociationsRegistered") {
      const auto* registered = std::get_if<bool>(call.arguments());
      if (!registered) {
        result->Error("bad_args", "Expected the registration preference");
        return;
      }
      const auto status = SetFileAssociationsRegistered(*registered);
      if (status == ERROR_SUCCESS) {
        result->Success();
      } else {
        result->Error("association_failed", std::to_string(status));
      }
    } else {
      result->NotImplemented();
    }
  });
}

bool FlutterWindow::ReceiveOpenFile(HWND hwnd, const COPYDATASTRUCT* data) {
  if (!data || data->dwData != kOpenFileMessage ||
      data->cbData > 32768 * sizeof(wchar_t) ||
      data->cbData % sizeof(wchar_t) != 0) {
    return false;
  }
  if (data->cbData != 0) {
    if (!data->lpData) return false;
    const auto* chars = static_cast<const wchar_t*>(data->lpData);
    std::wstring path(chars, data->cbData / sizeof(wchar_t));
    if (path.find(L'\0') != std::wstring::npos ||
        !std::filesystem::path(path).is_absolute() || !IsSupportedOpenPath(path)) {
      return false;
    }
    pending_files_.push_back(std::move(path));
    if (external_open_) external_open_->InvokeMethod("filesAvailable", nullptr);
  }
  if (IsWindowVisible(hwnd)) {
    if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
    SetForegroundWindow(hwnd);
  }
  return true;
}

void FlutterWindow::OnDestroy() {
  if (external_open_) {
    external_open_->SetMethodCallHandler(nullptr);
    external_open_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_COPYDATA) {
    return ReceiveOpenFile(hwnd, reinterpret_cast<const COPYDATASTRUCT*>(lparam));
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
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
