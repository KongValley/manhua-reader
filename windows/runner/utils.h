#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// Reads absolute paths for supported launch arguments.
// 读取支持的启动参数并解析为绝对路径。
std::vector<std::wstring> GetOpenFileArguments();
bool IsSupportedOpenPath(const std::wstring& path);
std::wstring GetExecutablePath();

// Registers this executable as an optional Windows Open with choice.
// 将此可执行文件注册为 Windows“打开方式”的可选程序。
bool AreFileAssociationsRegistered();
long SetFileAssociationsRegistered(bool registered);

#endif  // RUNNER_UTILS_H_
