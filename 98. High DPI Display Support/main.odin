package d3d11_demo

import helpers "../0. Helpers"
import win "core:sys/windows"
import "core:os"
import "core:time"
import "core:fmt"

// https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows

WINDOW_NAME :: "98. High DPI Display Support"

assert_messagebox :: helpers.assert_messagebox


dpi         : u32  = win.USER_DEFAULT_SCREEN_DPI // 96
dpi_scale   : f32  = 1                           // dpi / default
dpi_changed : bool = false

wnd_proc :: proc "stdcall" (hWnd: win.HWND, uMsg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) -> (result: win.LRESULT) {
        result = 0

        switch uMsg {
        case win.WM_DPICHANGED:
                dpi_changed = true
                dpi         = win.GetDpiForWindow(hWnd)
                dpi_scale   = f32(dpi) / 96.0

        case win.WM_KEYDOWN: 
                if wParam == win.VK_ESCAPE {
                        win.DestroyWindow(hWnd)
                }

        case win.WM_DESTROY:
                win.PostQuitMessage(0)

        case:
                result = win.DefWindowProcW(hWnd, uMsg, wParam, lParam)
        }

        return
}


main :: proc() {
        hInstance := win.HINSTANCE(win.GetModuleHandleW(nil))

        // Available DPI awareness contexts:
        //      - Unaware        : all windows are 96 DPI
        //      - System         : all windows are the DPI of the system's primary display
        //      - Per-Monitor    : DPI is from the display the window is mostly located on
        //      - Per-Monitor V2 : Same as V1, but non-client area elements, themed common controls (buttons, etc), and dialogs are automatically scaled
        win.SetProcessDpiAwarenessContext(win.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)

        // Open a window
        hWnd: win.HWND
        {
                window_class := win.WNDCLASSEXW {
                        cbSize        = size_of(win.WNDCLASSEXW),
                        style         = win.CS_HREDRAW | win.CS_VREDRAW,
                        lpfnWndProc   = wnd_proc,
                        hInstance     = hInstance,
                        hIcon         = win.LoadIconW(nil, transmute(win.wstring)(win.IDI_APPLICATION)),
                        hCursor       = win.LoadCursorW(nil, transmute(win.wstring)(win.IDC_ARROW)),
                        lpszClassName = win.L(WINDOW_NAME),
                        hIconSm       = win.LoadIconW(nil, transmute(win.wstring)(win.IDI_APPLICATION)),
                }

                class_atom := win.RegisterClassExW(&window_class)
                assert_messagebox(class_atom != 0, "RegisterClassExW failed!")

                hWnd = win.CreateWindowExW(
                        dwExStyle    = win.WS_EX_OVERLAPPEDWINDOW,
                        lpClassName  = window_class.lpszClassName,
                        lpWindowName = win.L(WINDOW_NAME),
                        dwStyle      = win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE,
                        X            = win.CW_USEDEFAULT, // i32 min value
                        Y            = win.CW_USEDEFAULT,
                        nWidth       = win.CW_USEDEFAULT,
                        nHeight      = win.CW_USEDEFAULT,
                        hWndParent   = nil,
                        hMenu        = nil,
                        hInstance    = hInstance,
                        lpParam      = nil,
                )
                assert_messagebox(hWnd != nil, "CreateWindowExW failed!")
        }

        // Get current DPI for window
        {
                dpi       = win.GetDpiForWindow(hWnd)
                dpi_scale = f32(dpi) / win.USER_DEFAULT_SCREEN_DPI
                fmt.printfln("Current DPI = %v, scale = %v", dpi, dpi_scale)
        }


        // Game loop
        is_running := true
        for is_running {
                msg: win.MSG
                for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
                        if msg.message == win.WM_QUIT {
                                is_running = false
                        }
                        win.TranslateMessage(&msg)
                        win.DispatchMessageW(&msg)
                }

                if dpi_changed {
                        fmt.printfln("DPI Changed! dpi = %v, scale = %v", dpi, dpi_scale)
                        dpi_changed = false
                }

                time.sleep(time.Millisecond * 16) // Note: inaccurate timer 
        }
}
