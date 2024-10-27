package d3d11_demo

import helpers "../0. Helpers"
import win "core:sys/windows"
import "core:os"
import "core:time"

WINDOW_NAME :: "00. Opening a Win32 Window"

L                 :: helpers.L
as_lstring        :: helpers.as_lstring
assert_messagebox :: helpers.assert_messagebox


wnd_proc :: proc "stdcall" (hWnd: win.HWND, uMsg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) -> (result: win.LRESULT) {
        result = 0

        switch uMsg {
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

        // Open a window
        hWnd: win.HWND
        {
                window_class := win.WNDCLASSEXW {
                        cbSize        = size_of(win.WNDCLASSEXW),
                        style         = win.CS_HREDRAW | win.CS_VREDRAW,
                        lpfnWndProc   = wnd_proc,
                        hInstance     = hInstance,
                        hIcon         = win.LoadIconW(nil, as_lstring(win.IDI_APPLICATION)),
                        hCursor       = win.LoadCursorW(nil, as_lstring(win.IDC_ARROW)),
                        lpszClassName = L(WINDOW_NAME),
                        hIconSm       = win.LoadIconW(nil, as_lstring(win.IDI_APPLICATION)),
                }

                class_atom := win.RegisterClassExW(&window_class)
                assert_messagebox(class_atom != 0, L("RegisterClassExW failed!"))

                hWnd = win.CreateWindowExW(
                        dwExStyle    = win.WS_EX_OVERLAPPEDWINDOW,
                        lpClassName  = window_class.lpszClassName,
                        lpWindowName = L(WINDOW_NAME),
                        dwStyle      = win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE,
                        X            = win.CW_USEDEFAULT, // i32 min value
                        Y            = win.CW_USEDEFAULT,
                        nWidth       = win.CW_USEDEFAULT,
                        nHeight      = win.CW_USEDEFAULT,
                        hWndParent   = nil,
                        hMenu        = nil,
                        hInstance    = hInstance,
                        lpParam      = nil
                )
                assert_messagebox(hWnd != nil, L("CreateWindowExW failed!"))
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

                time.accurate_sleep(time.Millisecond * 16)
        }
}
