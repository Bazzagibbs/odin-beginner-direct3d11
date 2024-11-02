package d3d11_demo

import helpers "../0. Helpers"
import "base:intrinsics"
import win "core:sys/windows"
import "core:os"
import "core:time"
import "core:fmt"
import "vendor:directx/d3d11"
import "vendor:directx/dxgi"

WINDOW_NAME :: "01. Initialising Direct3D"

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
                        hIcon         = win.LoadIconW(nil, transmute(win.wstring)(win.IDI_APPLICATION)),
                        hCursor       = win.LoadCursorW(nil, transmute(win.wstring)(win.IDC_ARROW)),
                        lpszClassName = win.L(WINDOW_NAME),
                        hIconSm       = win.LoadIconW(nil, transmute(win.wstring)(win.IDI_APPLICATION)),
                }

                class_atom := win.RegisterClassExW(&window_class)
                assert_messagebox(class_atom != 0, "RegisterClassExW failed")

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
                        lpParam      = nil
                )

                assert_messagebox(hWnd != nil, "CreateWindowExW failed")
        }

        // Create D3D11 Device and Context
        device         : ^d3d11.IDevice
        device_context : ^d3d11.IDeviceContext
        {
                feature_levels := []d3d11.FEATURE_LEVEL { d3d11.FEATURE_LEVEL._11_0 }
                creation_flags := d3d11.CREATE_DEVICE_FLAGS { .BGRA_SUPPORT }
                when ODIN_DEBUG {
                        creation_flags += {.DEBUG}
                }

                res := d3d11.CreateDevice(
                        pAdapter           = nil,
                        DriverType         = .HARDWARE,
                        Software           = nil,
                        Flags              = creation_flags,
                        pFeatureLevels     = raw_data(feature_levels),
                        FeatureLevels      = u32(len(feature_levels)),
                        SDKVersion         = d3d11.SDK_VERSION,
                        ppDevice           = &device,
                        pFeatureLevel      = nil,
                        ppImmediateContext = &device_context,
                )

                assert_messagebox(res, "CreateDevice() failed")
        }


        // Debug layer
        when ODIN_DEBUG {
                device_debug: ^d3d11.IDebug
                device->QueryInterface(d3d11.IDebug_UUID, (^rawptr)(&device_debug))
                if device_debug != nil {
                        info_queue: ^d3d11.IInfoQueue
                        res := device_debug->QueryInterface(d3d11.IInfoQueue_UUID, (^rawptr)(&info_queue))
                        if win.SUCCEEDED(res) {
                                info_queue->SetBreakOnSeverity(.CORRUPTION, true)
                                info_queue->SetBreakOnSeverity(.ERROR, true)

                                allow_severities := []d3d11.MESSAGE_SEVERITY {.CORRUPTION, .ERROR, .INFO}

                                filter := d3d11.INFO_QUEUE_FILTER {
                                        AllowList = {
                                                NumSeverities = u32(len(allow_severities)),
                                                pSeverityList = raw_data(allow_severities),
                                        },
                                }
                                info_queue->AddStorageFilterEntries(&filter)
                                info_queue->Release()
                        }
                        defer device_debug->Release()
                }
        }


        // Create swapchain
        swapchain: ^dxgi.ISwapChain1
        {
                factory: ^dxgi.IFactory2
                {
                        dxgi_device: ^dxgi.IDevice1
                        res := device->QueryInterface(dxgi.IDevice1_UUID, (^rawptr)(&dxgi_device))
                        defer dxgi_device->Release()
                        assert_messagebox(res, "DXGI device interface query failed")

                        dxgi_adapter: ^dxgi.IAdapter
                        res  = dxgi_device->GetAdapter(&dxgi_adapter)
                        defer dxgi_adapter->Release()
                        assert_messagebox(res, "DXGI adapter interface query failed")

                        adapter_desc: dxgi.ADAPTER_DESC
                        dxgi_adapter->GetDesc(&adapter_desc)
                        fmt.printfln("Graphics device: %s", adapter_desc.Description)

                        res = dxgi_adapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&factory))
                        assert_messagebox(res, "Get DXGI Factory failed")
                }
                defer factory->Release()

                swapchain_desc := dxgi.SWAP_CHAIN_DESC1 {
                        Width       = 0, // use window width/height
                        Height      = 0,
                        Format      = .B8G8R8A8_UNORM_SRGB,
                        SampleDesc  = {
                                Count   = 1,
                                Quality = 0,
                        },
                        BufferUsage = {.RENDER_TARGET_OUTPUT},
                        BufferCount = 2,
                        Scaling     = .STRETCH,
                        SwapEffect  = .DISCARD,
                        AlphaMode   = .UNSPECIFIED,
                        Flags       = {},
                }

                res := factory->CreateSwapChainForHwnd(
                        pDevice           = device,
                        hWnd              = hWnd,
                        pDesc             = &swapchain_desc,
                        pFullscreenDesc   = nil,
                        pRestrictToOutput = nil,
                        ppSwapChain       = &swapchain
                )
                assert_messagebox(res, "CreateSwapChain failed")
        }


        // Create Framebuffer Render Target
        framebuffer_view: ^d3d11.IRenderTargetView
        {
                framebuffer: ^d3d11.ITexture2D
                res := swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&framebuffer))
                assert_messagebox(res, "Get Framebuffer failed")
                defer framebuffer->Release()

                res  = device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view)
                assert_messagebox(res, "CreateRenderTargetView failed")
        }


        // Game loop
        bg_color := [4]f32 {0, 0.4, 0.6, 1}
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

                // Change background color over time
                bg_color.r += 0.01
                if bg_color.r > 0.5 {
                        bg_color.r -= 0.5
                }

                device_context->ClearRenderTargetView(framebuffer_view, &bg_color)
                swapchain->Present(1, {})
                time.sleep(time.Millisecond * 16)
        }
}
