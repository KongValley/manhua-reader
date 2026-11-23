#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>

#include <filesystem>
#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  // First, find the length of the string with a safe upper bound (CWE-126).
  // UNICODE_STRING_MAX_CHARS (32767) is the maximum length of a UNICODE_STRING.
  int input_length = static_cast<int>(wcsnlen(utf16_string, UNICODE_STRING_MAX_CHARS));
  // Now use that bounded length to determine the required buffer size.
  // When an explicit length is passed, WideCharToMultiByte does not include
  // the null terminator in its returned size.
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 || static_cast<size_t>(target_length) > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

namespace {
constexpr const wchar_t* kBookExtensions[] = {L".pdf", L".mobi", L".cbz"};
constexpr wchar_t kReaderProgId[] = L"Manhua.Reader.Book";
constexpr wchar_t kReaderClass[] = L"Software\\Classes\\Manhua.Reader.Book";
constexpr wchar_t kReaderCommand[] =
    L"Software\\Classes\\Manhua.Reader.Book\\shell\\open\\command";

std::wstring OpenWithKey(const wchar_t* extension) {
  return std::wstring(L"Software\\Classes\\") + extension + L"\\OpenWithProgids";
}

std::wstring OpenCommand(const std::wstring& executable) {
  return L"\"" + executable + L"\" \"%1\"";
}

LSTATUS SetRegistryValue(const std::wstring& path, const wchar_t* name,
                         DWORD type, const void* value, DWORD bytes) {
  return RegSetKeyValueW(HKEY_CURRENT_USER, path.c_str(), name, type, value,
                         bytes);
}

LSTATUS SetRegistryString(const std::wstring& path, const std::wstring& value) {
  return SetRegistryValue(path, nullptr, REG_SZ, value.c_str(),
                          static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
}

LSTATUS RemoveFileAssociations() {
  LSTATUS status = ERROR_SUCCESS;
  for (const auto* extension : kBookExtensions) {
    const auto result = RegDeleteKeyValueW(HKEY_CURRENT_USER,
                                           OpenWithKey(extension).c_str(),
                                           kReaderProgId);
    if (result != ERROR_SUCCESS && result != ERROR_FILE_NOT_FOUND &&
        result != ERROR_PATH_NOT_FOUND) {
      status = result;
    }
  }
  const auto result = RegDeleteTreeW(HKEY_CURRENT_USER, kReaderClass);
  if (result != ERROR_SUCCESS && result != ERROR_FILE_NOT_FOUND &&
      result != ERROR_PATH_NOT_FOUND) {
    status = result;
  }
  return status;
}
}  // namespace

bool IsSupportedOpenPath(const std::wstring& path) {
  const auto extension = std::filesystem::path(path).extension().wstring();
  for (const auto* supported : kBookExtensions) {
    if (_wcsicmp(extension.c_str(), supported) == 0) return true;
  }
  return false;
}

std::vector<std::wstring> GetOpenFileArguments() {
  std::vector<std::wstring> files;
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) return files;

  for (int index = 1; index < argc; ++index) {
    if (!IsSupportedOpenPath(argv[index])) continue;
    const DWORD needed = GetFullPathNameW(argv[index], 0, nullptr, nullptr);
    if (needed == 0 || needed > 32768) continue;
    std::wstring path(needed, L'\0');
    const DWORD length = GetFullPathNameW(argv[index], needed, path.data(), nullptr);
    if (length > 0 && length < needed) {
      path.resize(length);
      files.push_back(std::move(path));
    }
  }
  LocalFree(argv);
  return files;
}

std::wstring GetExecutablePath() {
  std::wstring path(32768, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, path.data(),
                                          static_cast<DWORD>(path.size()));
  if (length == 0 || length >= path.size()) return {};
  path.resize(length);
  return path;
}

bool AreFileAssociationsRegistered() {
  const auto executable = GetExecutablePath();
  if (executable.empty()) return false;
  const auto command = OpenCommand(executable);
  std::wstring stored(command.size() + 1, L'\0');
  DWORD bytes = static_cast<DWORD>(stored.size() * sizeof(wchar_t));
  if (RegGetValueW(HKEY_CURRENT_USER, kReaderCommand, nullptr, RRF_RT_REG_SZ,
                   nullptr, stored.data(), &bytes) != ERROR_SUCCESS ||
      command != stored.c_str()) {
    return false;
  }
  for (const auto* extension : kBookExtensions) {
    if (RegGetValueW(HKEY_CURRENT_USER, OpenWithKey(extension).c_str(),
                     kReaderProgId, RRF_RT_REG_NONE, nullptr, nullptr,
                     nullptr) != ERROR_SUCCESS) {
      return false;
    }
  }
  return true;
}

long SetFileAssociationsRegistered(bool registered) {
  LSTATUS result;
  if (registered) {
    const auto executable = GetExecutablePath();
    if (executable.empty()) return ERROR_FILE_NOT_FOUND;

    // OpenWithProgids adds a choice without changing the user's defaults.
    // OpenWithProgids 仅提供候选程序，不更改用户的默认设置。
    result = SetRegistryString(kReaderClass, L"\u6F2B\u9605");
    if (result == ERROR_SUCCESS) {
      result = SetRegistryString(kReaderCommand, OpenCommand(executable));
    }
    if (result == ERROR_SUCCESS) {
      result = SetRegistryString(std::wstring(kReaderClass) + L"\\DefaultIcon",
                                 L"\"" + executable + L"\",0");
    }
    for (const auto* extension : kBookExtensions) {
      if (result != ERROR_SUCCESS) break;
      result = SetRegistryValue(OpenWithKey(extension), kReaderProgId,
                                REG_NONE, nullptr, 0);
    }
    if (result != ERROR_SUCCESS) RemoveFileAssociations();
  } else {
    result = RemoveFileAssociations();
  }
  SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
  return result;
}
