#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

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

  // Fail loudly instead of silently when the app is started from inside the
  // zip (Windows extracts only the .exe to a temp folder) or files are missing.
  {
    wchar_t exe[MAX_PATH];
    ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring dir(exe);
    dir = dir.substr(0, dir.find_last_of(L"\\/"));
    const wchar_t* needed[] = {L"\\flutter_windows.dll", L"\\data\\app.so",
                               L"\\data\\icudtl.dat", L"\\sqlite3.dll"};
    for (auto n : needed) {
      if (::GetFileAttributesW((dir + n).c_str()) == INVALID_FILE_ATTRIBUTES) {
        ::MessageBoxW(nullptr,
                      (L"Gerekli dosya bulunamad\u0131:\n" + dir + n +
                       L"\n\nZip dosyas\u0131n\u0131 \u00f6nce sa\u011f t\u0131k > \"T\u00fcm\u00fcn\u00fc ay\u0131kla\" ile bir klas\u00f6re \u00e7\u0131kar\u0131n, "
                       L"sonra o klas\u00f6rdeki VocaBloom.exe'yi \u00e7al\u0131\u015ft\u0131r\u0131n.")
                          .c_str(),
                      L"VocaBloom", MB_OK | MB_ICONERROR);
        return EXIT_FAILURE;
      }
    }
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"VocaBloom", origin, size)) {
    ::MessageBoxW(nullptr,
                  L"VocaBloom penceresi a\u00e7\u0131lamad\u0131 (Flutter motoru ba\u015flat\u0131lamad\u0131).\n"
                  L"Ekran kart\u0131 s\u00fcr\u00fcc\u00fcn\u00fcz\u00fc g\u00fcncelleyip tekrar deneyin.",
                  L"VocaBloom", MB_OK | MB_ICONERROR);
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
