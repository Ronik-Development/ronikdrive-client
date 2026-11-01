#include "desktop_drive.h"
#include <flutter/standard_method_codec.h>
#include <winhttp.h>
#include <shlobj.h>
#include <shellapi.h>
#include <sddl.h>
#include <aclapi.h>
#include <winioctl.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Provider.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <algorithm>
#include <future>
#include <vector>
#include <cwctype>
#include <stdexcept>
#include <sstream>
#include <iostream>
#include <wincrypt.h>

#define CF_SIZE_OF_OP_PARAM(member) (FIELD_OFFSET(CF_OPERATION_PARAMETERS, member) + sizeof(((CF_OPERATION_PARAMETERS*)0)->member))

using winrt::Windows::Data::Json::JsonObject;
using winrt::Windows::Data::Json::JsonValue;
using namespace winrt::Windows::Storage::Provider;
namespace {
constexpr size_t kMaxBytes = 64 * 1024 * 1024;
constexpr NTSTATUS kUnavailable = static_cast<NTSTATUS>(0xC000CF01L);
constexpr NTSTATUS kDenied = static_cast<NTSTATUS>(0xC0000022L);
struct InternetHandle {
  HINTERNET handle;
  ~InternetHandle() { if (handle) WinHttpCloseHandle(handle); }
};
struct FileHandle {
  HANDLE handle;
  ~FileHandle() { if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle); }
};
struct SensitiveBytes {
  std::vector<uint8_t> bytes;
  explicit SensitiveBytes(size_t size) : bytes(size) {}
  ~SensitiveBytes() { if (!bytes.empty()) SecureZeroMemory(bytes.data(), bytes.size()); }
};
struct LocalAllocation {
  void* value = nullptr;
  ~LocalAllocation() { if (value) LocalFree(value); }
};
void Require(bool condition) { if (!condition) throw std::runtime_error("drive-unavailable"); }
std::wstring Arg(const flutter::EncodableMap& args, const char* key) {
  auto it = args.find(flutter::EncodableValue(key));
  Require(it != args.end() && std::holds_alternative<std::string>(it->second));
  return winrt::to_hstring(std::get<std::string>(it->second)).c_str();
}
JsonObject Identity(const CF_CALLBACK_INFO* info) {
  Require(info->FileIdentity && info->FileIdentityLength > 0 && info->FileIdentityLength <= 4096);
  return JsonObject::Parse(winrt::to_hstring(std::string(
    static_cast<const char*>(info->FileIdentity), info->FileIdentityLength)));
}
CF_OPERATION_INFO Operation(const CF_CALLBACK_INFO* info, CF_OPERATION_TYPE type) {
  CF_OPERATION_INFO op{};
  op.StructSize = sizeof(op);
  op.Type = type;
  op.ConnectionKey = info->ConnectionKey;
  op.TransferKey = info->TransferKey;
  op.RequestKey = info->RequestKey;
  return op;
}
bool SafeName(const std::wstring& name) {
  if (name.empty() || name.size() > 255 || name == L"." || name == L".." ||
      name.back() == L'.' || name.back() == L' ') return false;
  for (wchar_t c : name) if (c < 32 || wcschr(L"<>:\"/\\|?*", c)) return false;
  auto base = name.substr(0, name.find(L'.'));
  while (!base.empty() && base.back() == L' ') base.pop_back();
  std::transform(base.begin(), base.end(), base.begin(), ::towupper);
  if (base == L"CON" || base == L"PRN" || base == L"AUX" || base == L"NUL" ||
      base == L"CONIN$" || base == L"CONOUT$") return false;
  if (base.size() == 4 && (base.substr(0, 3) == L"COM" || base.substr(0, 3) == L"LPT") &&
      wcschr(L"123456789¹²³", base[3])) return false;
  return true;
}
// Pin each directory without delete sharing for the whole operation. Checking
// the final component alone permits an ancestor junction to escape the root.
std::vector<std::unique_ptr<FileHandle>> PinParents(const std::wstring& root, const std::wstring& path) {
  Require(path.size() > root.size() && _wcsnicmp(path.c_str(), root.c_str(), root.size()) == 0 && path[root.size()] == L'\\');
  std::vector<std::unique_ptr<FileHandle>> handles;
  size_t end = root.size();
  while (true) {
    const auto directory = path.substr(0, end);
    auto handle = std::make_unique<FileHandle>();
    handle->handle = CreateFileW(directory.c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    Require(handle->handle != INVALID_HANDLE_VALUE);
    FILE_ATTRIBUTE_TAG_INFO tag{};
    Require(GetFileInformationByHandleEx(handle->handle, FileAttributeTagInfo, &tag, sizeof(tag)));
    Require(tag.FileAttributes & FILE_ATTRIBUTE_DIRECTORY);
    const auto cloudState = CfGetPlaceholderStateFromAttributeTag(tag.FileAttributes, tag.ReparseTag);
    Require(!(tag.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
      (cloudState & (end == root.size() ? CF_PLACEHOLDER_STATE_SYNC_ROOT : CF_PLACEHOLDER_STATE_PLACEHOLDER)));
    handles.push_back(std::move(handle));
    const auto next = path.find(L'\\', end + 1);
    Require(SafeName(path.substr(end + 1, next == std::wstring::npos ? next : next - end - 1)));
    if (next == std::wstring::npos) break;
    end = next;
    Require(handles.size() <= 64);
  }
  return handles;
}
USN ReadUsn(HANDLE handle) {
  alignas(USN_RECORD_V2) BYTE data[4096]{};
  DWORD count = 0;
  Require(DeviceIoControl(handle, FSCTL_READ_FILE_USN_DATA, nullptr, 0,
    data, sizeof(data), &count, nullptr));
  Require(count >= FIELD_OFFSET(USN_RECORD_V2, FileName));
  auto record = reinterpret_cast<const USN_RECORD_V2*>(data);
  Require(record->MajorVersion == 2 && record->Usn != 0);
  return record->Usn;
}
std::string Encode(const JsonObject& json) { return winrt::to_string(json.Stringify()); }
std::string ItemIdentity(const JsonObject& item) {
  JsonObject identity;
  identity.SetNamedValue(L"id", item.GetNamedValue(L"id"));
  identity.SetNamedValue(L"version", item.GetNamedValue(L"version"));
  return Encode(identity);
}
void TransferError(const CF_CALLBACK_INFO* info, NTSTATUS status) {
  auto op = Operation(info, CF_OPERATION_TYPE_TRANSFER_DATA);
  CF_OPERATION_PARAMETERS p{};
  p.ParamSize = CF_SIZE_OF_OP_PARAM(TransferData);
  p.TransferData.CompletionStatus = status;
  p.TransferData.Offset.QuadPart = 0;
  p.TransferData.Length = info->FileSize;
  CfExecute(&op, &p);
}
}

DesktopDrive::DesktopDrive(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
    messenger, "ronikcloud/desktop-drive", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    try {
      if (call.method_name() == "inspect") {
        Require(connected_ && call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments()));
        const auto name = Arg(std::get<flutter::EncodableMap>(*call.arguments()), "name");
        Require(SafeName(name));
        const auto path = root_ + L"\\" + name;
        const auto parents = PinParents(root_, path);
        FileHandle file{CreateFileW(path.c_str(), FILE_READ_ATTRIBUTES,
          FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
          FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr)};
        Require(file.handle != INVALID_HANDLE_VALUE);
        alignas(CF_PLACEHOLDER_STANDARD_INFO) char buffer[8192]{};
        const auto status = CfGetPlaceholderInfo(file.handle, CF_PLACEHOLDER_INFO_STANDARD, buffer, sizeof(buffer), nullptr);
        flutter::EncodableMap inspection;
        inspection[flutter::EncodableValue("inSync")] = flutter::EncodableValue(false);
        if (SUCCEEDED(status)) {
          const auto info = reinterpret_cast<const CF_PLACEHOLDER_STANDARD_INFO*>(buffer);
          Require(info->FileIdentityLength > 0 && FIELD_OFFSET(CF_PLACEHOLDER_STANDARD_INFO, FileIdentity) + info->FileIdentityLength <= sizeof(buffer));
          inspection[flutter::EncodableValue("inSync")] = flutter::EncodableValue(info->InSyncState == CF_IN_SYNC_STATE_IN_SYNC);
          inspection[flutter::EncodableValue("identity")] = flutter::EncodableValue(std::string(
            reinterpret_cast<const char*>(info->FileIdentity), info->FileIdentityLength));
        }
        result->Success(flutter::EncodableValue(inspection)); return;
      }
      if (call.method_name() == "openFolder") {
        Require(call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments()));
        const auto domain = Arg(std::get<flutter::EncodableMap>(*call.arguments()), "domain");
        Require(domain.size() == 64 && domain.find_first_not_of(L"0123456789abcdef") == std::wstring::npos);
        PWSTR profile = nullptr;
        winrt::check_hresult(SHGetKnownFolderPath(FOLDERID_Profile, 0, nullptr, &profile));
        const std::wstring path = std::wstring(profile) + L"\\RonikCloud-" + domain.substr(0, 16);
        CoTaskMemFree(profile);
        const auto pinned = PinParents(path, path + L"\\open-guard");
        Require(reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", path.c_str(),
          nullptr, nullptr, SW_SHOWNORMAL)) > 32);
        result->Success(); return;
      }
      if (call.method_name() == "remove") {
        Stop();
        if (!registration_id_.empty()) {
          std::async(std::launch::async, [this]() {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
            StorageProviderSyncRootManager::Unregister(registration_id_);
          }).get();
        }
        result->Success(); return;
      }
      if (call.method_name() == "stop" || call.method_name() == "disconnect") {
        Stop(); result->Success(); return;
      }
      if (call.method_name() == "heartbeat") {
        result->Success(flutter::EncodableValue(!connected_ ? "paused" :
          sync_errors_ ? "needs-attention" : syncing_ ? "syncing" : "connected"));
        return;
      }
      if (call.method_name() != "start") { result->NotImplemented(); return; }
      Require(call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments()));
      const auto args = std::get<flutter::EncodableMap>(*call.arguments());
      // WinRT async .get() must run in an MTA, not Flutter's STA.
      std::async(std::launch::async, [this, args]() {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        Start(args);
      }).get();
      result->Success(flutter::EncodableValue(winrt::to_string(root_)));
    } catch (const winrt::hresult_error& error) {
      // Numeric Windows status only: no paths, tokens or account metadata.
      result->Error("unavailable", "File Explorer integration could not start.",
        flutter::EncodableValue(static_cast<int64_t>(error.code().value)));
    } catch (...) {
      result->Error("unavailable", "File Explorer integration could not start.");
    }
  });
}
DesktopDrive::~DesktopDrive() { channel_->SetMethodCallHandler(nullptr); Stop(); }

void DesktopDrive::Start(const flutter::EncodableMap& args) {
  Stop();
  const auto domain = Arg(args, "domain");
  Require(domain.size() == 64 && domain.find_first_not_of(L"0123456789abcdef") == std::wstring::npos);
  const auto token = Arg(args, "token");
  Require(token.size() == 44 && token.find_first_not_of(L"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=") == std::wstring::npos);
  auto portValue = args.at(flutter::EncodableValue("port"));
  int64_t port = std::holds_alternative<int32_t>(portValue)
    ? std::get<int32_t>(portValue) : std::get<int64_t>(portValue);
  Require(port >= 1024 && port <= 65535);
  PWSTR profile = nullptr;
  winrt::check_hresult(SHGetKnownFolderPath(FOLDERID_Profile, 0, nullptr, &profile));
  std::wstring base(profile); CoTaskMemFree(profile);
  // Per-account/environment root; never attach an arbitrary user-supplied path.
  root_ = base + L"\\RonikCloud-" + domain.substr(0, 16);
  HANDLE rawToken = INVALID_HANDLE_VALUE;
  Require(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &rawToken));
  FileHandle processToken{rawToken};
  DWORD tokenSize = 0;
  GetTokenInformation(processToken.handle, TokenUser, nullptr, 0, &tokenSize);
  Require(tokenSize > 0);
  std::vector<char> tokenInfo(tokenSize);
  Require(GetTokenInformation(processToken.handle, TokenUser, tokenInfo.data(), tokenSize, &tokenSize));
  const auto user = reinterpret_cast<const TOKEN_USER*>(tokenInfo.data());
  LPWSTR sidText = nullptr;
  Require(ConvertSidToStringSidW(user->User.Sid, &sidText));
  LocalAllocation sidAllocation{sidText};
  const std::wstring sid(sidText);
  registration_id_ = L"RonikCloud!" + sid + L"!" + domain;
  const auto sddl = L"D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;" + sid + L")";
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  Require(ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1, &descriptor, nullptr));
  LocalAllocation descriptorAllocation{descriptor};
  SECURITY_ATTRIBUTES security{sizeof(SECURITY_ATTRIBUTES), descriptor, FALSE};
  Require(CreateDirectoryW(root_.c_str(), &security) || GetLastError() == ERROR_ALREADY_EXISTS);
  // Hold the root without delete sharing while checking and registering it.
  FileHandle rootHandle{CreateFileW(root_.c_str(), READ_CONTROL | WRITE_DAC,
    FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr)};
  Require(rootHandle.handle != INVALID_HANDLE_VALUE);
  FILE_ATTRIBUTE_TAG_INFO rootTag{};
  Require(GetFileInformationByHandleEx(rootHandle.handle, FileAttributeTagInfo, &rootTag, sizeof(rootTag)));
  const bool existingSyncRoot = (CfGetPlaceholderStateFromAttributeTag(
    rootTag.FileAttributes, rootTag.ReparseTag) & CF_PLACEHOLDER_STATE_SYNC_ROOT) != 0;
  Require((rootTag.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) &&
    (!(rootTag.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) || existingSyncRoot));
  if (existingSyncRoot) {
    const auto folder = winrt::Windows::Storage::StorageFolder::GetFolderFromPathAsync(root_).get();
    Require(StorageProviderSyncRootManager::GetSyncRootInformationForFolder(folder).Id() == registration_id_);
  }
  PSID owner = nullptr;
  PSECURITY_DESCRIPTOR existingSecurity = nullptr;
  Require(GetSecurityInfo(rootHandle.handle, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION,
    &owner, nullptr, nullptr, nullptr, &existingSecurity) == ERROR_SUCCESS);
  LocalAllocation existingAllocation{existingSecurity};
  Require(owner && EqualSid(owner, user->User.Sid));
  BOOL daclPresent = FALSE, daclDefaulted = FALSE;
  PACL dacl = nullptr;
  Require(GetSecurityDescriptorDacl(descriptor, &daclPresent, &dacl, &daclDefaulted) && daclPresent);
  Require(SetSecurityInfo(rootHandle.handle, SE_FILE_OBJECT,
    DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
    nullptr, nullptr, dacl, nullptr) == ERROR_SUCCESS);
  const DWORD attributes = GetFileAttributesW(root_.c_str());
  Require(attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) &&
      (!(attributes & FILE_ATTRIBUTE_REPARSE_POINT) || existingSyncRoot));
  wchar_t volume[MAX_PATH]{}, fs[MAX_PATH]{};
  Require(GetVolumePathNameW(root_.c_str(), volume, MAX_PATH));
  Require(GetVolumeInformationW(volume, nullptr, 0, nullptr, nullptr, nullptr, fs, MAX_PATH));
  Require(_wcsicmp(fs, L"NTFS") == 0);
  registration_id_ = L"RonikCloud!" + sid + L"!" + domain;
  StorageProviderSyncRootInfo registration;
  registration.Id(registration_id_);
  registration.Path(winrt::Windows::Storage::StorageFolder::GetFolderFromPathAsync(root_).get());
  registration.DisplayNameResource(L"RonikCloud");
  wchar_t executable[32768]{};
  Require(GetModuleFileNameW(nullptr, executable, 32768) > 0);
  registration.IconResource(std::wstring(executable) + L",-101");
  registration.Version(L"1.0.0");
  registration.HydrationPolicy(StorageProviderHydrationPolicy::Full);
  registration.PopulationPolicy(StorageProviderPopulationPolicy::Full);
  registration.InSyncPolicy(StorageProviderInSyncPolicy::FileCreationTime | StorageProviderInSyncPolicy::DirectoryCreationTime);
  JsonObject rootIdentity;
  rootIdentity.SetNamedValue(L"id", JsonValue::CreateStringValue(L"root"));
  rootIdentity.SetNamedValue(L"version", JsonValue::CreateStringValue(L"1"));
  registration.Context(winrt::Windows::Security::Cryptography::CryptographicBuffer::ConvertStringToBinary(
    rootIdentity.Stringify(), winrt::Windows::Security::Cryptography::BinaryStringEncoding::Utf8));
  StorageProviderSyncRootManager::Register(registration);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    token_ = token; port_ = static_cast<unsigned short>(port);
  }
  const CF_CALLBACK_REGISTRATION callbacks[] = {
    {CF_CALLBACK_TYPE_FETCH_DATA, FetchData},
    {CF_CALLBACK_TYPE_FETCH_PLACEHOLDERS, FetchPlaceholders},
    {CF_CALLBACK_TYPE_NOTIFY_DELETE, NotifyDelete},
    {CF_CALLBACK_TYPE_NOTIFY_RENAME, NotifyRename},
    {CF_CALLBACK_TYPE_NOTIFY_FILE_CLOSE_COMPLETION, NotifyClose},
    CF_CALLBACK_REGISTRATION_END};
  winrt::check_hresult(CfConnectSyncRoot(root_.c_str(), callbacks, this,
    static_cast<CF_CONNECT_FLAGS>(CF_CONNECT_FLAG_REQUIRE_FULL_FILE_PATH |
      CF_CONNECT_FLAG_REQUIRE_PROCESS_INFO), &connection_));
  connected_ = true;
  LoadBaselines();
  // Explorer does not request population for an empty registered sync root.
  // Seed its authoritative listing after connection; child directories are
  // populated on demand by FetchPlaceholders.
  const auto items = JsonObject::Parse(Arg(args, "rootItems")).GetNamedArray(L"items");
  Require(items.Size() <= 10000);
  std::vector<std::wstring> names;
  std::vector<std::string> identities;
  std::vector<CF_PLACEHOLDER_CREATE_INFO> entries(items.Size());
  names.reserve(items.Size()); identities.reserve(items.Size());
  for (uint32_t i = 0; i < items.Size(); ++i) {
    const auto item = items.GetObjectAt(i);
    names.emplace_back(item.GetNamedString(L"name"));
    Require(SafeName(names.back()));
    identities.push_back(ItemIdentity(item));
    auto& entry = entries[i];
    entry.RelativeFileName = names.back().c_str();
    entry.FileIdentity = identities.back().data();
    entry.FileIdentityLength = static_cast<DWORD>(identities.back().size());
    entry.FsMetadata.BasicInfo.FileAttributes = item.GetNamedBoolean(L"directory")
      ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
    const auto size = item.GetNamedNumber(L"size");
    Require(size >= 0 && size <= static_cast<double>(kMaxBytes));
    entry.FsMetadata.FileSize.QuadPart = static_cast<LONGLONG>(size);
    entry.Flags = CF_PLACEHOLDER_CREATE_FLAG_MARK_IN_SYNC;
  }
  // Reconnection must preserve existing dirty files, including editor-created
  // replacements that no longer have placeholder metadata.
  entries.erase(std::remove_if(entries.begin(), entries.end(), [this](const auto& entry) {
    const auto path = root_ + L"\\" + entry.RelativeFileName;
    const auto attributes = GetFileAttributesW(path.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES) return true;
    Require(GetLastError() == ERROR_FILE_NOT_FOUND);
    return false;
  }), entries.end());
  if (!entries.empty()) {
    DWORD processed = 0;
    const auto created = CfCreatePlaceholders(root_.c_str(), entries.data(),
      static_cast<DWORD>(entries.size()), CF_CREATE_FLAG_NONE, &processed);
    if (created != HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS) &&
        created != HRESULT_FROM_WIN32(ERROR_FILE_EXISTS)) winrt::check_hresult(created);
    for (const auto& entry : entries) {
      if (entry.Result != HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS) &&
          entry.Result != HRESULT_FROM_WIN32(ERROR_FILE_EXISTS)) {
        winrt::check_hresult(entry.Result);
      }
    }
  }
  refresh_thread_ = std::thread([this]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    while (connected_) {
      sync_errors_ = 0;
      syncing_ = true;
      try { RefreshDirectory(root_, "root", 0); }
      catch (const winrt::hresult_error& error) {
        ++sync_errors_;
        std::cerr << "[native-drive] scan status=" << error.code().value << '\n';
      } catch (...) {
        ++sync_errors_;
        std::cerr << "[native-drive] scan unavailable status=" << GetLastError() << '\n';
      }
      syncing_ = false;
      std::unique_lock<std::mutex> lock(refresh_mutex_);
      refresh_wake_.wait_for(lock, std::chrono::seconds(10), [this]() { return !connected_; });
    }
  });
}

void DesktopDrive::Stop() {
  { std::lock_guard<std::mutex> lock(mutex_); token_.clear(); port_ = 0; }
  if (connected_.exchange(false)) CfDisconnectSyncRoot(connection_);
  refresh_wake_.notify_all();
  if (refresh_thread_.joinable()) refresh_thread_.join();
  // Keep registration and local files: disconnect must not delete unsynced work.
}

// Reconcile ordinary local creates and retry dirty placeholders. File IDs and
// creation times survive process restarts, so create retries are idempotent.
std::string DesktopDrive::SyncLocal(const std::wstring& path,
    const std::string& parent, const std::wstring& name) {
  const char* stage = "open";
  try {
  Require(connected_ && SafeName(name));
  const auto parents = PinParents(root_, path);
  FileHandle file{CreateFileW(path.c_str(), GENERIC_READ | WRITE_DAC,
    FILE_SHARE_READ, nullptr, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr)};
  Require(file.handle != INVALID_HANDLE_VALUE);
  FILE_ATTRIBUTE_TAG_INFO tag{};
  Require(GetFileInformationByHandleEx(file.handle, FileAttributeTagInfo, &tag, sizeof(tag)));
  const bool directory = (tag.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
  const bool placeholder = (CfGetPlaceholderStateFromAttributeTag(tag.FileAttributes,
    tag.ReparseTag) & CF_PLACEHOLDER_STATE_PLACEHOLDER) != 0;
  Require(!(tag.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) || placeholder);
  JsonObject payload;
  bool updating = placeholder;
  if (placeholder) {
    stage = "placeholder-identity";
    alignas(CF_PLACEHOLDER_STANDARD_INFO) char buffer[8192]{};
    winrt::check_hresult(CfGetPlaceholderInfo(file.handle, CF_PLACEHOLDER_INFO_STANDARD,
      buffer, sizeof(buffer), nullptr));
    const auto info = reinterpret_cast<const CF_PLACEHOLDER_STANDARD_INFO*>(buffer);
    Require(info->FileIdentityLength > 0 && FIELD_OFFSET(CF_PLACEHOLDER_STANDARD_INFO,
      FileIdentity) + info->FileIdentityLength <= sizeof(buffer));
    payload = JsonObject::Parse(winrt::to_hstring(std::string(
      reinterpret_cast<const char*>(info->FileIdentity), info->FileIdentityLength)));
    if (directory || info->InSyncState == CF_IN_SYNC_STATE_IN_SYNC) {
      RecordBaseline(path, Encode(payload));
      return winrt::to_string(payload.GetNamedString(L"id"));
    }
  } else {
    const auto baseline = Baseline(path);
    if (!baseline.empty() && !directory) {
      // Editors often replace a file instead of modifying its placeholder.
      // Only an acknowledged, protected baseline authorizes a versioned update.
      payload = JsonObject::Parse(winrt::to_hstring(baseline));
      updating = true;
    } else {
    BY_HANDLE_FILE_INFORMATION info{};
    Require(GetFileInformationByHandle(file.handle, &info));
    std::ostringstream identity;
    identity << std::hex << info.dwVolumeSerialNumber << '-' << info.nFileIndexHigh
      << '-' << info.nFileIndexLow << '-' << info.ftCreationTime.dwHighDateTime
      << '-' << info.ftCreationTime.dwLowDateTime;
    payload.SetNamedValue(L"requestId", JsonValue::CreateStringValue(winrt::to_hstring(identity.str())));
    payload.SetNamedValue(L"parentId", JsonValue::CreateStringValue(winrt::to_hstring(parent)));
    payload.SetNamedValue(L"name", JsonValue::CreateStringValue(name));
    payload.SetNamedValue(L"directory", JsonValue::CreateBooleanValue(directory));
    }
  }
  stage = "read-usn";
  const auto originalUsn = ReadUsn(file.handle);
  LARGE_INTEGER size{};
  if (!directory) Require(GetFileSizeEx(file.handle, &size));
  Require(size.QuadPart >= 0 && size.QuadPart <= static_cast<LONGLONG>(kMaxBytes));
  stage = "read-content";
  SensitiveBytes sensitive(static_cast<size_t>(size.QuadPart));
  if (!directory) {
    DWORD read = 0;
    Require(ReadFile(file.handle, sensitive.bytes.data(), static_cast<DWORD>(sensitive.bytes.size()), &read, nullptr));
    Require(read == sensitive.bytes.size());
  }
  payload.SetNamedValue(L"contents", JsonValue::CreateStringValue(
    winrt::Windows::Security::Cryptography::CryptographicBuffer::EncodeToBase64String(
      winrt::Windows::Security::Cryptography::CryptographicBuffer::CreateFromByteArray(sensitive.bytes))));
  stage = "cloud-mutation";
  const auto item = JsonObject::Parse(winrt::to_hstring(Request(
    updating ? L"/v1/update" : L"/v1/create", Encode(payload))));
  const auto identity = ItemIdentity(item);
  RecordBaseline(path, identity);
  stage = "placeholder-acknowledgement";
  USN usn = originalUsn;
  Require(connected_);
  if (placeholder) {
    winrt::check_hresult(CfUpdatePlaceholder(file.handle, nullptr, identity.data(),
      static_cast<DWORD>(identity.size()), nullptr, 0, CF_UPDATE_FLAG_MARK_IN_SYNC, &usn, nullptr));
  } else {
    // The held handle denies write/delete sharing throughout the upload.
    // Read-side metadata can change the USN without changing file contents.
    winrt::check_hresult(CfConvertToPlaceholder(file.handle, identity.data(),
      static_cast<DWORD>(identity.size()), CF_CONVERT_FLAG_MARK_IN_SYNC, &usn, nullptr));
  }
  return winrt::to_string(item.GetNamedString(L"id"));
  } catch (...) {
    std::cerr << "[native-drive] failed stage=" << stage << '\n';
    throw;
  }
}

void DesktopDrive::RefreshDirectory(const std::wstring& path,
    const std::string& parent, unsigned depth) {
  Require(connected_ && depth < 64);
  // Hold ancestors throughout enumeration to reject junction replacement.
  const auto pinned = PinParents(root_, path + L"\\enumeration-guard");
  RefreshRemote(path, parent);
  WIN32_FIND_DATAW entry{};
  HANDLE search = FindFirstFileW((path + L"\\*").c_str(), &entry);
  if (search == INVALID_HANDLE_VALUE) {
    Require(GetLastError() == ERROR_FILE_NOT_FOUND);
    return;
  }
  struct SearchGuard { HANDLE handle; ~SearchGuard() { FindClose(handle); } } guard{search};
  size_t count = 0;
  do {
    if (!connected_) return;
    const std::wstring name(entry.cFileName);
    if (name == L"." || name == L"..") continue;
    Require(++count <= 10000 && SafeName(name));
    try {
      const auto child = path + L"\\" + name;
      const auto id = SyncLocal(child, parent, name);
      if (entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
        RefreshDirectory(child, id, depth + 1);
    } catch (const winrt::hresult_error& error) {
      ++sync_errors_;
      std::cerr << "[native-drive] sync status=" << error.code().value << '\n';
    } catch (...) {
      ++sync_errors_;
      std::cerr << "[native-drive] sync unavailable status=" << GetLastError() << '\n';
    }
  } while (FindNextFileW(search, &entry));
  Require(GetLastError() == ERROR_NO_MORE_FILES);
}

void DesktopDrive::RefreshRemote(const std::wstring& path, const std::string& parent) {
  JsonObject query;
  query.SetNamedValue(L"parentId", JsonValue::CreateStringValue(winrt::to_hstring(parent)));
  const auto items = JsonObject::Parse(winrt::to_hstring(Request(L"/v1/list", Encode(query)))).GetNamedArray(L"items");
  Require(items.Size() <= 10000);
  for (const auto& value : items) {
    Require(connected_);
    const auto item = value.GetObject();
    const std::wstring name(item.GetNamedString(L"name"));
    Require(SafeName(name));
    const auto identity = ItemIdentity(item);
    const auto filePath = path + L"\\" + name;
    const auto pinned = PinParents(root_, filePath);
    const bool directory = item.GetNamedBoolean(L"directory");
    const auto size = item.GetNamedNumber(L"size");
    Require(size >= 0 && size <= static_cast<double>(kMaxBytes));
    CF_PLACEHOLDER_CREATE_INFO entry{};
    entry.RelativeFileName = name.c_str();
    entry.FileIdentity = identity.data();
    entry.FileIdentityLength = static_cast<DWORD>(identity.size());
    entry.FsMetadata.BasicInfo.FileAttributes = directory ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
    entry.FsMetadata.FileSize.QuadPart = static_cast<LONGLONG>(size);
    entry.Flags = CF_PLACEHOLDER_CREATE_FLAG_MARK_IN_SYNC;
    const auto attributes = GetFileAttributesW(filePath.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) {
      Require(GetLastError() == ERROR_FILE_NOT_FOUND);
      DWORD processed = 0;
      const auto created = CfCreatePlaceholders(path.c_str(), &entry, 1, CF_CREATE_FLAG_NONE, &processed);
      if (created != HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS) &&
          created != HRESULT_FROM_WIN32(ERROR_FILE_EXISTS)) winrt::check_hresult(created);
      if (SUCCEEDED(created) && SUCCEEDED(entry.Result)) continue;
      if (FAILED(entry.Result) && entry.Result != HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS) &&
          entry.Result != HRESULT_FROM_WIN32(ERROR_FILE_EXISTS)) winrt::check_hresult(entry.Result);
    }
    // Pin the leaf without following a reparse point before using the CFAPI
    // opener (which resolves paths). Deny replacement throughout the operation.
    FileHandle leaf{CreateFileW(filePath.c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr)};
    if (leaf.handle == INVALID_HANDLE_VALUE) continue;
    FILE_ATTRIBUTE_TAG_INFO leafTag{};
    Require(GetFileInformationByHandleEx(leaf.handle, FileAttributeTagInfo, &leafTag, sizeof(leafTag)));
    if (!(CfGetPlaceholderStateFromAttributeTag(leafTag.FileAttributes, leafTag.ReparseTag) & CF_PLACEHOLDER_STATE_PLACEHOLDER)) continue;
    // CFAPI's exclusive oplock yields to foreground apps instead of making
    // Explorer opens fail with sharing violations during background refresh.
    struct ProtectedFile {
      HANDLE protectedHandle = INVALID_HANDLE_VALUE;
      HANDLE handle = INVALID_HANDLE_VALUE;
      bool referenced = false;
      ~ProtectedFile() {
        if (referenced) CfReleaseProtectedHandle(protectedHandle);
        if (protectedHandle != INVALID_HANDLE_VALUE) CfCloseHandle(protectedHandle);
      }
    } file;
    if (FAILED(CfOpenFileWithOplock(filePath.c_str(), static_cast<CF_OPEN_FILE_FLAGS>(
        CF_OPEN_FILE_FLAG_EXCLUSIVE | CF_OPEN_FILE_FLAG_WRITE_ACCESS), &file.protectedHandle))) continue;
    file.referenced = CfReferenceProtectedHandle(file.protectedHandle) != FALSE;
    if (!file.referenced) continue;
    file.handle = CfGetWin32HandleFromProtectedHandle(file.protectedHandle);
    FILE_ATTRIBUTE_TAG_INFO tag{};
    Require(GetFileInformationByHandleEx(file.handle, FileAttributeTagInfo, &tag, sizeof(tag)));
    if (!(CfGetPlaceholderStateFromAttributeTag(tag.FileAttributes, tag.ReparseTag) & CF_PLACEHOLDER_STATE_PLACEHOLDER)) continue;
    alignas(CF_PLACEHOLDER_STANDARD_INFO) char buffer[8192]{};
    winrt::check_hresult(CfGetPlaceholderInfo(file.handle, CF_PLACEHOLDER_INFO_STANDARD, buffer, sizeof(buffer), nullptr));
    const auto info = reinterpret_cast<const CF_PLACEHOLDER_STANDARD_INFO*>(buffer);
    Require(info->FileIdentityLength > 0 && FIELD_OFFSET(CF_PLACEHOLDER_STANDARD_INFO, FileIdentity) + info->FileIdentityLength <= sizeof(buffer));
    const auto previous = JsonObject::Parse(winrt::to_hstring(std::string(
      reinterpret_cast<const char*>(info->FileIdentity), info->FileIdentityLength)));
    if (previous.GetNamedString(L"id") != item.GetNamedString(L"id") ||
        previous.GetNamedString(L"version") == item.GetNamedString(L"version") ||
        info->InSyncState != CF_IN_SYNC_STATE_IN_SYNC) continue;
    // The exclusive handle denies writers/replacements; VERIFY_IN_SYNC guards
    // dirty content. Read-side hydration can advance USNs independently.
    USN usn = 0;
    const auto flags = static_cast<CF_UPDATE_FLAGS>(CF_UPDATE_FLAG_VERIFY_IN_SYNC |
      CF_UPDATE_FLAG_MARK_IN_SYNC | (directory ? 0 : CF_UPDATE_FLAG_DEHYDRATE));
    winrt::check_hresult(CfUpdatePlaceholder(file.handle, &entry.FsMetadata, identity.data(),
      static_cast<DWORD>(identity.size()), nullptr, 0, flags, &usn, nullptr));
    RecordBaseline(filePath, identity);
  }
}

std::string DesktopDrive::Baseline(const std::wstring& path) {
  auto key = path.substr(root_.size());
  std::transform(key.begin(), key.end(), key.begin(), ::towupper);
  std::lock_guard<std::mutex> lock(baseline_mutex_);
  const auto found = baselines_.find(key);
  return found == baselines_.end() ? std::string() : found->second;
}

void DesktopDrive::LoadBaselines() {
  std::lock_guard<std::mutex> lock(baseline_mutex_);
  baselines_.clear();
  // An NTFS alternate stream is not enumerated/uploaded with user files.
  // DPAPI binds this acknowledgement journal to the OS user and sync identity.
  FileHandle file{CreateFileW((root_ + L":RonikCloud.NativeState").c_str(), GENERIC_READ,
    FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr)};
  if (file.handle == INVALID_HANDLE_VALUE) return;
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file.handle, &size) || size.QuadPart <= 0 || size.QuadPart > 8 * 1024 * 1024) return;
  SensitiveBytes data(static_cast<size_t>(size.QuadPart));
  DWORD read = 0;
  if (!ReadFile(file.handle, data.bytes.data(), static_cast<DWORD>(data.bytes.size()), &read, nullptr) || read != data.bytes.size()) return;
  DATA_BLOB input{read, data.bytes.data()}, output{};
  DATA_BLOB entropy{static_cast<DWORD>(registration_id_.size() * sizeof(wchar_t)), reinterpret_cast<BYTE*>(registration_id_.data())};
  if (!CryptUnprotectData(&input, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) return;
  LocalAllocation allocation{output.pbData};
  try {
    const auto json = JsonObject::Parse(winrt::to_hstring(std::string(reinterpret_cast<char*>(output.pbData), output.cbData)));
    Require(json.Size() <= 10000);
    for (const auto& pair : json) baselines_.emplace(pair.Key().c_str(), winrt::to_string(pair.Value().GetString()));
  } catch (...) { baselines_.clear(); }
  SecureZeroMemory(output.pbData, output.cbData);
}

void DesktopDrive::RecordBaseline(const std::wstring& path, const std::string& identity) {
  Require(path.size() > root_.size() && path[root_.size()] == L'\\');
  auto key = path.substr(root_.size());
  std::transform(key.begin(), key.end(), key.begin(), ::towupper);
  std::lock_guard<std::mutex> lock(baseline_mutex_);
  const auto previous = baselines_.find(key);
  if (previous != baselines_.end() && previous->second == identity) return;
  Require(baselines_.size() < 10000 || previous != baselines_.end());
  auto next = baselines_;
  next[key] = identity;
  JsonObject json;
  for (const auto& pair : next) json.SetNamedValue(pair.first, JsonValue::CreateStringValue(winrt::to_hstring(pair.second)));
  auto plain = Encode(json);
  struct Wipe { std::string& value; ~Wipe() { SecureZeroMemory(value.data(), value.size()); } } wipe{plain};
  Require(plain.size() < 8 * 1024 * 1024);
  DATA_BLOB input{static_cast<DWORD>(plain.size()), reinterpret_cast<BYTE*>(plain.data())}, output{};
  DATA_BLOB entropy{static_cast<DWORD>(registration_id_.size() * sizeof(wchar_t)), reinterpret_cast<BYTE*>(registration_id_.data())};
  Require(CryptProtectData(&input, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output));
  LocalAllocation allocation{output.pbData};
  FileHandle file{CreateFileW((root_ + L":RonikCloud.NativeState").c_str(), GENERIC_WRITE,
    0, nullptr, CREATE_ALWAYS, 0, nullptr)};
  Require(file.handle != INVALID_HANDLE_VALUE);
  DWORD written = 0;
  Require(WriteFile(file.handle, output.pbData, output.cbData, &written, nullptr) && written == output.cbData);
  Require(FlushFileBuffers(file.handle));
  baselines_ = std::move(next);
}

std::string DesktopDrive::Request(const std::wstring& route, const std::string& body) {
  std::wstring token; unsigned short port;
  { std::lock_guard<std::mutex> lock(mutex_); token = token_; port = port_; }
  Require(!token.empty() && port != 0 && body.size() <= kMaxBytes * 2);
  InternetHandle session{WinHttpOpen(L"RonikCloudDrive/1", WINHTTP_ACCESS_TYPE_NO_PROXY,
    WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0)};
  Require(session.handle != nullptr);
  WinHttpSetTimeouts(session.handle, 5000, 5000, 30000, 30000);
  InternetHandle connection{WinHttpConnect(session.handle, L"127.0.0.1", port, 0)};
  Require(connection.handle != nullptr);
  InternetHandle request{WinHttpOpenRequest(connection.handle, L"POST", route.c_str(),
    nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0)};
  Require(request.handle != nullptr);
  DWORD disabled = WINHTTP_DISABLE_REDIRECTS | WINHTTP_DISABLE_COOKIES;
  Require(WinHttpSetOption(request.handle, WINHTTP_OPTION_DISABLE_FEATURE, &disabled, sizeof(disabled)));
  const auto headers = L"Content-Type: application/json\r\nAuthorization: Bearer " + token + L"\r\n";
  Require(WinHttpSendRequest(request.handle, headers.c_str(), static_cast<DWORD>(-1),
    const_cast<char*>(body.data()), static_cast<DWORD>(body.size()), static_cast<DWORD>(body.size()), 0));
  Require(WinHttpReceiveResponse(request.handle, nullptr));
  DWORD status = 0, statusSize = sizeof(status);
  Require(WinHttpQueryHeaders(request.handle, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
    WINHTTP_HEADER_NAME_BY_INDEX, &status, &statusSize, WINHTTP_NO_HEADER_INDEX));
  if (status != 200) std::cerr << "[native-drive] broker status=" << status << '\n';
  Require(status == 200);
  std::string result; char buffer[65536]; DWORD read = 0;
  do {
    Require(WinHttpReadData(request.handle, buffer, sizeof(buffer), &read));
    Require(result.size() + read <= kMaxBytes);
    result.append(buffer, read);
  } while (read);
  { std::lock_guard<std::mutex> lock(mutex_); Require(token_ == token && port_ == port); }
  return result;
}

void CALLBACK DesktopDrive::FetchPlaceholders(const CF_CALLBACK_INFO* info, const CF_CALLBACK_PARAMETERS*) {
  auto self = static_cast<DesktopDrive*>(info->CallbackContext);
  auto op = Operation(info, CF_OPERATION_TYPE_TRANSFER_PLACEHOLDERS);
  CF_OPERATION_PARAMETERS p{};
  p.ParamSize = CF_SIZE_OF_OP_PARAM(TransferPlaceholders);
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    JsonObject query;
    const auto identity = info->FileIdentityLength ? Identity(info) : JsonObject{};
    query.SetNamedValue(L"parentId", JsonValue::CreateStringValue(identity.GetNamedString(L"id", L"root")));
    const auto result = JsonObject::Parse(winrt::to_hstring(self->Request(L"/v1/list", Encode(query))));
    const auto items = result.GetNamedArray(L"items");
    Require(items.Size() <= 10000);
    std::vector<std::wstring> names; std::vector<std::string> identities;
    std::vector<CF_PLACEHOLDER_CREATE_INFO> placeholders(items.Size());
    names.reserve(items.Size()); identities.reserve(items.Size());
    for (uint32_t i = 0; i < items.Size(); i++) {
      const auto item = items.GetObjectAt(i);
      names.emplace_back(item.GetNamedString(L"name"));
      Require(SafeName(names.back()));
      identities.push_back(ItemIdentity(item));
      auto& entry = placeholders[i];
      entry.RelativeFileName = names.back().c_str();
      entry.FileIdentity = identities.back().data();
      entry.FileIdentityLength = static_cast<DWORD>(identities.back().size());
      entry.FsMetadata.BasicInfo.FileAttributes = item.GetNamedBoolean(L"directory")
        ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
      entry.FsMetadata.FileSize.QuadPart = static_cast<LONGLONG>(item.GetNamedNumber(L"size"));
      entry.Flags = CF_PLACEHOLDER_CREATE_FLAG_MARK_IN_SYNC;
    }
    p.TransferPlaceholders.Flags = CF_OPERATION_TRANSFER_PLACEHOLDERS_FLAG_DISABLE_ON_DEMAND_POPULATION;
    p.TransferPlaceholders.CompletionStatus = 0;
    p.TransferPlaceholders.PlaceholderTotalCount.QuadPart = items.Size();
    p.TransferPlaceholders.PlaceholderCount = items.Size();
    p.TransferPlaceholders.PlaceholderArray = placeholders.data();
    CfExecute(&op, &p);
  } catch (...) {
    p.TransferPlaceholders.CompletionStatus = kUnavailable;
    CfExecute(&op, &p);
  }
}

void CALLBACK DesktopDrive::FetchData(const CF_CALLBACK_INFO* info, const CF_CALLBACK_PARAMETERS*) {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    auto self = static_cast<DesktopDrive*>(info->CallbackContext);
    auto bytes = self->Request(L"/v1/read", Encode(Identity(info)));
    struct Wipe { std::string& data; ~Wipe() { if (!data.empty()) SecureZeroMemory(data.data(), data.size()); } } wipe{bytes};
    Require(static_cast<LONGLONG>(bytes.size()) == info->FileSize.QuadPart);
    auto op = Operation(info, CF_OPERATION_TYPE_TRANSFER_DATA);
    CF_OPERATION_PARAMETERS p{};
    p.ParamSize = CF_SIZE_OF_OP_PARAM(TransferData);
    p.TransferData.CompletionStatus = 0;
    p.TransferData.Offset.QuadPart = 0;
    p.TransferData.Length.QuadPart = bytes.size();
    p.TransferData.Buffer = bytes.data();
    // Broker already completed MAC verification and the account check.
    std::lock_guard<std::mutex> lock(self->mutex_);
    Require(self->connected_ && !self->token_.empty());
    CfExecute(&op, &p);
  } catch (...) { TransferError(info, kUnavailable); }
}

void CALLBACK DesktopDrive::NotifyDelete(const CF_CALLBACK_INFO* info, const CF_CALLBACK_PARAMETERS*) {
  auto op = Operation(info, CF_OPERATION_TYPE_ACK_DELETE);
  CF_OPERATION_PARAMETERS p{}; p.ParamSize = CF_SIZE_OF_OP_PARAM(AckDelete);
  p.AckDelete.CompletionStatus = kDenied;
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    static_cast<DesktopDrive*>(info->CallbackContext)->Request(L"/v1/recycle", Encode(Identity(info)));
    p.AckDelete.CompletionStatus = 0;
  } catch (...) { /* Fail closed: preserve the user's local file. */ }
  CfExecute(&op, &p);
}
void CALLBACK DesktopDrive::NotifyRename(const CF_CALLBACK_INFO* info, const CF_CALLBACK_PARAMETERS*) {
  // Renames need a verified destination-parent identity. Never derive a cloud
  // path from the OS notification until that mapping is available.
  auto op = Operation(info, CF_OPERATION_TYPE_ACK_RENAME);
  CF_OPERATION_PARAMETERS p{}; p.ParamSize = CF_SIZE_OF_OP_PARAM(AckRename);
  p.AckRename.CompletionStatus = kDenied;
  CfExecute(&op, &p);
}
void CALLBACK DesktopDrive::NotifyClose(const CF_CALLBACK_INFO* info, const CF_CALLBACK_PARAMETERS* params) {
  // Provider reads/USN checks must not recursively trigger another upload.
  if (info->ProcessInfo && info->ProcessInfo->ProcessId == GetCurrentProcessId()) return;
  if (params->CloseCompletion.Flags & CF_CALLBACK_CLOSE_COMPLETION_FLAG_DELETED) return;
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    auto self = static_cast<DesktopDrive*>(info->CallbackContext);
    std::wstring path = std::wstring(info->VolumeDosName) + info->NormalizedPath;
    const auto parents = PinParents(self->root_, path);
    FileHandle file{CreateFileW(path.c_str(), GENERIC_READ | WRITE_DAC, FILE_SHARE_READ,
      nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr)};
    Require(file.handle != INVALID_HANDLE_VALUE);
    FILE_ATTRIBUTE_TAG_INFO tag{};
    Require(GetFileInformationByHandleEx(file.handle, FileAttributeTagInfo, &tag, sizeof(tag)));
    Require(!(tag.FileAttributes & FILE_ATTRIBUTE_DIRECTORY));
    Require(CfGetPlaceholderStateFromAttributeTag(tag.FileAttributes, tag.ReparseTag) & CF_PLACEHOLDER_STATE_PLACEHOLDER);
    alignas(CF_PLACEHOLDER_STANDARD_INFO) char standardBuffer[8192]{};
    winrt::check_hresult(CfGetPlaceholderInfo(file.handle, CF_PLACEHOLDER_INFO_STANDARD,
      standardBuffer, sizeof(standardBuffer), nullptr));
    const auto standard = reinterpret_cast<const CF_PLACEHOLDER_STANDARD_INFO*>(standardBuffer);
    if (standard->InSyncState == CF_IN_SYNC_STATE_IN_SYNC) return;
    LARGE_INTEGER size{}; Require(GetFileSizeEx(file.handle, &size));
    Require(size.QuadPart >= 0 && size.QuadPart <= static_cast<LONGLONG>(kMaxBytes));
    const auto originalUsn = ReadUsn(file.handle);
    SensitiveBytes sensitive(static_cast<size_t>(size.QuadPart));
    auto& bytes = sensitive.bytes;
    DWORD read = 0; Require(ReadFile(file.handle, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr));
    Require(read == bytes.size());
    Require(standard->FileIdentityLength > 0 &&
      FIELD_OFFSET(CF_PLACEHOLDER_STANDARD_INFO, FileIdentity) + standard->FileIdentityLength <= sizeof(standardBuffer));
    auto payload = JsonObject::Parse(winrt::to_hstring(std::string(
      static_cast<const char*>(static_cast<const void*>(standard->FileIdentity)), standard->FileIdentityLength)));
    payload.SetNamedValue(L"contents", JsonValue::CreateStringValue(
      winrt::Windows::Security::Cryptography::CryptographicBuffer::EncodeToBase64String(
        winrt::Windows::Security::Cryptography::CryptographicBuffer::CreateFromByteArray(bytes))));
    const auto item = JsonObject::Parse(winrt::to_hstring(self->Request(L"/v1/update", Encode(payload))));
    const auto identity = ItemIdentity(item);
    self->RecordBaseline(path, identity);
    USN usn = originalUsn;
    winrt::check_hresult(CfUpdatePlaceholder(file.handle, nullptr, identity.data(), static_cast<DWORD>(identity.size()),
      nullptr, 0, CF_UPDATE_FLAG_MARK_IN_SYNC, &usn, nullptr));
  } catch (...) { /* Leave modified content dirty and available for recovery. */ }
}
