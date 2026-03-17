#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>
#include <fcntl.h>

#include <iostream>

void RedirectIOToConsole() {
  // Force UTF-8 code page for consistent console output
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);

  FILE *unused;
  if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
    _dup2(_fileno(stdout), 1);
  }
  if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
    _dup2(_fileno(stdout), 2);
  }
  // optional: stdin
  freopen_s(&unused, "CONIN$", "r", stdin);
  // keep text mode with UTF-8 code page
  _setmode(_fileno(stdout), _O_TEXT);
  _setmode(_fileno(stderr), _O_TEXT);
  _setmode(_fileno(stdin), _O_TEXT);
  std::ios::sync_with_stdio();
  FlutterDesktopResyncOutputStreams();
}

bool AttachToParentConsole() {
  if (::AttachConsole(ATTACH_PARENT_PROCESS)) {
    RedirectIOToConsole();
    return true;
  }
  return false;
}

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    RedirectIOToConsole();
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
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
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
