#ifndef RONIKCLOUD_DESKTOP_DRIVE_H_
#define RONIKCLOUD_DESKTOP_DRIVE_H_
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <cfapi.h>
#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <condition_variable>
#include <map>

// CFAPI owns placeholders; this adapter owns no cloud or encryption keys.
class DesktopDrive {
 public:
  explicit DesktopDrive(flutter::BinaryMessenger* messenger);
  ~DesktopDrive();
 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  CF_CONNECTION_KEY connection_{};
  std::atomic<bool> connected_{false};
  std::atomic<unsigned> sync_errors_{0};
  std::atomic<bool> syncing_{false};
  std::mutex mutex_;
  std::wstring root_, registration_id_, token_;
  unsigned short port_ = 0;
  std::thread refresh_thread_;
  std::mutex refresh_mutex_;
  std::condition_variable refresh_wake_;
  void RefreshDirectory(const std::wstring& path, const std::string& parent, unsigned depth);
  void RefreshRemote(const std::wstring& path, const std::string& parent);
  std::mutex baseline_mutex_;
  std::map<std::wstring, std::string> baselines_;
  void LoadBaselines();
  void RecordBaseline(const std::wstring& path, const std::string& identity);
  std::string Baseline(const std::wstring& path);
  std::string SyncLocal(const std::wstring& path, const std::string& parent, const std::wstring& name);
  void Start(const flutter::EncodableMap& args);
  void Stop();
  static void CALLBACK FetchData(const CF_CALLBACK_INFO*, const CF_CALLBACK_PARAMETERS*);
  static void CALLBACK FetchPlaceholders(const CF_CALLBACK_INFO*, const CF_CALLBACK_PARAMETERS*);
  static void CALLBACK NotifyDelete(const CF_CALLBACK_INFO*, const CF_CALLBACK_PARAMETERS*);
  static void CALLBACK NotifyRename(const CF_CALLBACK_INFO*, const CF_CALLBACK_PARAMETERS*);
  static void CALLBACK NotifyClose(const CF_CALLBACK_INFO*, const CF_CALLBACK_PARAMETERS*);
  std::string Request(const std::wstring& route, const std::string& body);
};
#endif
