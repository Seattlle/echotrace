#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  auto set_current_directory_to_executable = []() {
    wchar_t path[MAX_PATH];
    const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (length == 0 || length == MAX_PATH) {
      return;
    }
    std::wstring full_path(path, length);
    const size_t last_slash = full_path.find_last_of(L"\\/");
    if (last_slash == std::wstring::npos) {
      return;
    }
    const std::wstring exe_dir = full_path.substr(0, last_slash);
    ::SetCurrentDirectoryW(exe_dir.c_str());
  };

  set_current_directory_to_executable();

  std::vector<std::string> command_line_arguments;
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv != nullptr) {
    for (int i = 1; i < argc; i++) {
      command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
    }
    ::LocalFree(argv);
  }

  auto has_cli_flag = [&command_line_arguments]() {
    for (const auto& arg : command_line_arguments) {
      if (arg == "-e" || arg == "--export" || arg == "-export") {
        return true;
      }
    }
    return false;
  };

  const bool cliMode = has_cli_flag();

  if (cliMode) {
    // CLI: force attach/create console and redirect output
    bool consoleAttached = AttachToParentConsole();
    if (!consoleAttached) {
      CreateAndAttachConsole();
      consoleAttached = true;
    }
    if (consoleAttached) {
      printf("EchoTrace Windows runner detected CLI flags, launching in console mode...\n");
      fflush(stdout);
    }

    // Handle console signals for CLI (Ctrl+C/close)
    SetConsoleCtrlHandler(
        [](DWORD ctrlType) -> BOOL {
          switch (ctrlType) {
            case CTRL_C_EVENT:
            case CTRL_BREAK_EVENT:
            case CTRL_CLOSE_EVENT:
            case CTRL_LOGOFF_EVENT:
            case CTRL_SHUTDOWN_EVENT:
              PostQuitMessage(0);
              return TRUE;
            default:
              return FALSE;
          }
        },
        TRUE);
  } else {
    // Non-CLI: keep default behavior, create console when debugging
    if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
      CreateAndAttachConsole();
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"echotrace", origin, size)) {
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
