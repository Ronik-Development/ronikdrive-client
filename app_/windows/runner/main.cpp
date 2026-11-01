#include <algorithm>
#include <exception>
#include <iostream>
#include <sstream>
#include <string>

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

void LogRunnerException(const char* context, const char* message = nullptr) {
  std::ostringstream stream;
  stream << "[runner] " << context;
  if (message != nullptr && message[0] != '\0') {
    stream << ": " << message;
  }
  stream << '\n';
  const auto output = stream.str();
  OutputDebugStringA(output.c_str());
  std::cerr << output;
}

}  // namespace

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
  project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnPlatformThread);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const bool is_background_worker =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                std::string("--background-backup-worker")) !=
      command_line_arguments.end() ||
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                std::string("--desktop-drive-worker")) !=
      command_line_arguments.end();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  if (is_background_worker) {
    window.SetShowOnStart(false);
  }
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(
          is_background_worker ? L"RonikCloud Background" : L"RonikCloud",
          origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    try {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    } catch (const std::exception& error) {
      LogRunnerException("DispatchMessage", error.what());
    } catch (...) {
      LogRunnerException("DispatchMessage", "unknown native exception");
    }
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
