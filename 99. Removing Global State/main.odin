package d3d11_demo

import helpers "../0. Helpers"
import win "core:sys/windows"
import "core:os"
import "core:time"
import "core:fmt"

WINDOW_NAME :: "99. Removing Global State"

assert_messagebox :: helpers.assert_messagebox


App_State :: struct {
        did_resize          : bool,
}


wnd_proc :: proc "stdcall" (hWnd: win.HWND, uMsg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) -> (result: win.LRESULT) {
        result = 0

        switch uMsg {
        case win.WM_CREATE:
                // Set app_state userptr for future messages, provided by the last parameter in win.CreateWindowExW()
                createstruct := transmute(^win.CREATESTRUCTW)lParam
                app_state := (^App_State)(createstruct.lpCreateParams)
                win.SetWindowLongPtrW(hWnd, win.GWLP_USERDATA, transmute(int)app_state)

        case win.WM_SIZE:
                // Get app_state userptr
                app_state := transmute(^App_State)win.GetWindowLongPtrW(hWnd, win.GWLP_USERDATA)
                app_state.did_resize = true

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

        app_state := App_State {}

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
                        lpParam      = &app_state // pass userptr to the wnd_proc
                )
                assert_messagebox(hWnd != nil, "CreateWindowExW failed!")
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

                if app_state.did_resize {
                        fmt.println("Resized!")
                        app_state.did_resize = false
                }

                time.sleep(time.Millisecond * 16) // Note: inaccurate timer 
        }
}
