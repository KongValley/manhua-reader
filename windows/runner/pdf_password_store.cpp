#include "pdf_password_store.h"

#include <windows.h>
#include <bcrypt.h>
#include <shlobj.h>
#include <wincrypt.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <array>
#include <filesystem>
#include <fstream>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

namespace fs = std::filesystem;
using flutter::EncodableMap;
using flutter::EncodableValue;

// Credential files stay in the local profile, outside the library and roaming data.
// 密码文件保存在本机用户配置目录中，与书库及漫游数据分开。
fs::path CredentialDirectory() {
  PWSTR local_app_data = nullptr;
  const HRESULT status = SHGetKnownFolderPath(
      FOLDERID_LocalAppData, 0, nullptr, &local_app_data);
  const std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> directory(
      local_app_data, CoTaskMemFree);
  if (FAILED(status)) {
    throw std::runtime_error("Cannot access the local profile");
  }
  return fs::path(directory.get()) / L"ManhuaReader" / L"PdfPasswords";
}

fs::path CredentialPath(const std::string& key) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr,
                                  0) < 0) {
    throw std::runtime_error("Cannot initialize SHA-256");
  }
  std::array<UCHAR, 32> digest{};
  const NTSTATUS status = BCryptHash(
      algorithm, nullptr, 0, reinterpret_cast<PUCHAR>(const_cast<char*>(key.data())),
      static_cast<ULONG>(key.size()), digest.data(),
      static_cast<ULONG>(digest.size()));
  BCryptCloseAlgorithmProvider(algorithm, 0);
  if (status < 0) throw std::runtime_error("Cannot hash credential key");

  constexpr char digits[] = "0123456789abcdef";
  std::string name;
  name.reserve(digest.size() * 2);
  for (const auto byte : digest) {
    name.push_back(digits[byte >> 4]);
    name.push_back(digits[byte & 0x0f]);
  }
  return CredentialDirectory() / name;
}

DATA_BLOB AsBlob(const std::string& input) {
  return {static_cast<DWORD>(input.size()),
          reinterpret_cast<BYTE*>(const_cast<char*>(input.data()))};
}

// DPAPI uses the current user and authenticates each entry with its own key.
// DPAPI 使用当前用户的凭据，并通过每条记录的键验证数据。
std::optional<std::string> ReadPassword(const fs::path& path,
                                        const std::string& key) {
  if (!fs::exists(path)) return std::nullopt;
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  const std::streamoff size = file.tellg();
  if (size <= 0 || size > 1024 * 1024) {
    throw std::runtime_error("Invalid credential file");
  }
  std::vector<BYTE> ciphertext(static_cast<size_t>(size));
  file.seekg(0);
  if (!file.read(reinterpret_cast<char*>(ciphertext.data()), size)) {
    throw std::runtime_error("Cannot read credential file");
  }
  DATA_BLOB encrypted{static_cast<DWORD>(ciphertext.size()), ciphertext.data()};
  DATA_BLOB entropy = AsBlob(key);
  DATA_BLOB plaintext{};
  if (!CryptUnprotectData(&encrypted, nullptr, &entropy, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &plaintext)) {
    throw std::runtime_error("Cannot decrypt credential");
  }
  const auto wipe_and_free = [size = plaintext.cbData](BYTE* data) {
    SecureZeroMemory(data, size);
    LocalFree(data);
  };
  const std::unique_ptr<BYTE, decltype(wipe_and_free)> cleartext(
      plaintext.pbData, wipe_and_free);
  return std::string(reinterpret_cast<const char*>(cleartext.get()),
                     plaintext.cbData);
}

void WritePassword(const fs::path& path, const std::string& key,
                   const std::string& password) {
  DATA_BLOB plaintext = AsBlob(password);
  DATA_BLOB entropy = AsBlob(key);
  DATA_BLOB encrypted{};
  if (!CryptProtectData(&plaintext, nullptr, &entropy, nullptr, nullptr,
                        CRYPTPROTECT_UI_FORBIDDEN, &encrypted)) {
    throw std::runtime_error("Cannot encrypt credential");
  }
  const std::unique_ptr<BYTE, decltype(&LocalFree)> ciphertext(encrypted.pbData,
                                                             LocalFree);

  fs::create_directories(path.parent_path());
  std::array<wchar_t, MAX_PATH> temporary{};
  if (!GetTempFileNameW(path.parent_path().c_str(), L"pdf", 0,
                        temporary.data())) {
    throw std::runtime_error("Cannot create credential file");
  }
  try {
    std::ofstream file(fs::path(temporary.data()), std::ios::binary);
    file.write(reinterpret_cast<const char*>(ciphertext.get()),
               encrypted.cbData);
    file.close();
    if (!file || !MoveFileExW(temporary.data(), path.c_str(),
                              MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
      throw std::runtime_error("Cannot replace credential file");
    }
  } catch (...) {
    DeleteFileW(temporary.data());
    throw;
  }
}

const std::string* StringArgument(const EncodableMap& args, const char* name) {
  const auto entry = args.find(EncodableValue(name));
  return entry == args.end() ? nullptr : std::get_if<std::string>(&entry->second);
}

}  // namespace

void RegisterPdfPasswordStore(flutter::BinaryMessenger* messenger) {
  flutter::MethodChannel<EncodableValue> channel(
      messenger, "manhua/pdf_password_store",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler([](
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    const auto* key = args ? StringArgument(*args, "key") : nullptr;
    if (!key || key->empty()) {
      result->Error("bad_args", "Missing credential key");
      return;
    }
    const auto* password = StringArgument(*args, "password");
    try {
      const auto path = CredentialPath(*key);
      if (call.method_name() == "contains") {
        result->Success(EncodableValue(fs::exists(path)));
      } else if (call.method_name() == "read") {
        const auto value = ReadPassword(path, *key);
        if (value) {
          result->Success(EncodableValue(*value));
        } else {
          result->Success();
        }
      } else if (call.method_name() == "write") {
        if (!password || password->empty()) {
          result->Error("bad_args", "Missing password");
          return;
        }
        WritePassword(path, *key, *password);
        result->Success();
      } else if (call.method_name() == "delete") {
        if (!password || ReadPassword(path, *key) == *password) {
          fs::remove(path);
        }
        result->Success();
      } else {
        result->NotImplemented();
      }
    } catch (const std::exception&) {
      result->Error("pdf_password_store", "Secure storage is unavailable");
    }
  });
}
