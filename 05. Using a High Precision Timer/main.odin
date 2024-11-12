package d3d11_demo

import helpers "../0. Helpers"
import win "core:sys/windows"
import "core:time"
import "core:fmt"
import "core:math"
import "core:slice"
import "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"

WINDOW_NAME :: "05. Using a High Precision Timer"

assert_messagebox :: helpers.assert_messagebox

did_resize : bool

wnd_proc :: proc "stdcall" (hWnd: win.HWND, uMsg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) -> (result: win.LRESULT) {
        result = 0

        switch uMsg {
        case win.WM_KEYDOWN: 
                if wParam == win.VK_ESCAPE {
                        win.DestroyWindow(hWnd)
                }

        case win.WM_DESTROY:
                win.PostQuitMessage(0)

        case win.WM_SIZE:
                did_resize = true

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
                        X            = win.CW_USEDEFAULT, // i32 min value, not zero
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

        // Provide a pointer to the app state to the wndproc

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
        defer device->Release()
        defer device_context->Release()


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
                        device_debug->Release()
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
        defer swapchain->Release()


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
        defer framebuffer_view->Release()


        shader_src := #load("shaders.hlsl")

        // Create vertex shader
        vertex_shader_blob: ^d3d11.IBlob // used for InputLayout creation
        vertex_shader: ^d3d11.IVertexShader
        {
                // Note: this step can be performed offline. Save the blob buffer to a file using GetBufferPointer().
                compile_errors: ^d3d11.IBlob

                res := d3d_compiler.Compile(
                        pSrcData    = raw_data(shader_src),
                        SrcDataSize = uint(len(shader_src)),
                        pSourceName = "shaders.hlsl", // Not required, used for debug messages
                        pDefines    = nil,
                        pInclude    = nil,
                        pEntrypoint = "vertex_main",
                        pTarget     = "vs_5_0",
                        Flags1      = 0,
                        Flags2      = 0,
                        ppCode      = &vertex_shader_blob,
                        ppErrorMsgs = &compile_errors,
                )

                if win.FAILED(res) {
                        if compile_errors != nil {
                                error_str := compile_errors->GetBufferPointer()
                                fmt.eprintln(error_str)
                                compile_errors->Release()
                        }
                        assert_messagebox(res, "Vertex shader compilation failed")
                }

                res = device->CreateVertexShader(
                        pShaderBytecode = vertex_shader_blob->GetBufferPointer(),
                        BytecodeLength  = vertex_shader_blob->GetBufferSize(),
                        pClassLinkage   = nil,
                        ppVertexShader  = &vertex_shader
                )
                assert_messagebox(res, "Vertex shader creation failed")
        }
        defer vertex_shader_blob->Release()
        defer vertex_shader->Release()


        // Create pixel shader
        pixel_shader: ^d3d11.IPixelShader
        {
                pixel_shader_blob: ^d3d11.IBlob
                compile_errors: ^d3d11.IBlob

                res := d3d_compiler.Compile(
                        pSrcData    = raw_data(shader_src),
                        SrcDataSize = uint(len(shader_src)),
                        pSourceName = "shaders.hlsl", // Not required, used for debug messages
                        pDefines    = nil,
                        pInclude    = nil,
                        pEntrypoint = "pixel_main",
                        pTarget     = "ps_5_0",
                        Flags1      = 0,
                        Flags2      = 0,
                        ppCode      = &pixel_shader_blob,
                        ppErrorMsgs = &compile_errors,
                )
                defer pixel_shader_blob->Release()

                if win.FAILED(res) {
                        if compile_errors != nil {
                                error_str := compile_errors->GetBufferPointer()
                                fmt.eprintln(error_str)
                                compile_errors->Release()
                        }
                        assert_messagebox(res, "Pixel shader compilation failed")
                }

                res = device->CreatePixelShader(
                        pShaderBytecode = pixel_shader_blob->GetBufferPointer(),
                        BytecodeLength  = pixel_shader_blob->GetBufferSize(),
                        pClassLinkage   = nil,
                        ppPixelShader   = &pixel_shader
                )
                assert_messagebox(res, "Pixel shader creation failed")
        }
        defer pixel_shader->Release()


        // Create input layout
        input_layout: ^d3d11.IInputLayout
        {
                input_element_descs := []d3d11.INPUT_ELEMENT_DESC {
                        {
                                SemanticName         = "position",
                                SemanticIndex        = 0,
                                Format               = .R32G32_FLOAT,
                                InputSlot            = 0,
                                AlignedByteOffset    = 0,
                                InputSlotClass       = .VERTEX_DATA,
                                InstanceDataStepRate = 0,
                        }, 
                }

                res := device->CreateInputLayout(
                        pInputElementDescs                = raw_data(input_element_descs),
                        NumElements                       = u32(len(input_element_descs)),
                        pShaderBytecodeWithInputSignature = vertex_shader_blob->GetBufferPointer(),
                        BytecodeLength                    = vertex_shader_blob->GetBufferSize(),
                        ppInputLayout                     = &input_layout
                )
                assert_messagebox(res, "Input layout creation failed")
                // vertex_shader_blob is safe to release now
        }
        defer input_layout->Release()


        // Create vertex buffer
        vertex_buffer: ^d3d11.IBuffer
        vertex_count: u32
        vertex_stride: u32
        vertex_offset: u32
        {      
                vertex_data := []f32 {
                //      x,    y,   
                        0,    0.5, 
                        0.5,  -0.5,
                        -0.5, -0.5,
                }
                vertex_stride = size_of(f32) * 2
                vertex_count  = u32(len(vertex_data) / 2)
                vertex_offset = 0

                vertex_buffer_desc := d3d11.BUFFER_DESC {
                        ByteWidth = u32(slice.size(vertex_data)),
                        Usage     = .IMMUTABLE,
                        BindFlags = {.VERTEX_BUFFER},
                }

                vertex_subresource_data := d3d11.SUBRESOURCE_DATA { 
                        pSysMem = raw_data(vertex_data)
                }

                res := device->CreateBuffer(
                        pDesc        = &vertex_buffer_desc,
                        pInitialData = &vertex_subresource_data,
                        ppBuffer     = &vertex_buffer
                )
                assert_messagebox(res, "Create VertexBuffer failed")
        }
        defer vertex_buffer->Release()

        
        Constants :: struct #align(16) {
                position   : [2]f32,
                // padding : [8]byte, // (from #align directive. Constant buffers must be 16-byte aligned.)
                color      : [4]f32,
        }

        constant_buffer : ^d3d11.IBuffer
        {
                #assert(size_of(Constants) % 16 == 0, "Constant buffer size must be a multiple of 16")

                buffer_desc := d3d11.BUFFER_DESC {
                        ByteWidth      = size_of(Constants),
                        Usage          = .DYNAMIC,
                        BindFlags      = {.CONSTANT_BUFFER},
                        CPUAccessFlags = {.WRITE},
                }

                res := device->CreateBuffer(
                        pDesc = &buffer_desc, 
                        pInitialData = nil,
                        ppBuffer = &constant_buffer
                )
                assert_messagebox(res, "Create ConstantBuffer failed")
        }
        defer constant_buffer->Release()


        // Game loop
        is_running         := true
        triangle_spin      : f32 = 0
        triangle_spin_rate : f32 = math.TAU / 5 // One rotation per five seconds

        stopwatch : time.Stopwatch
        time.stopwatch_start(&stopwatch)

        for is_running {
                delta_duration := time.stopwatch_duration(stopwatch)
                time.stopwatch_reset(&stopwatch)
                time.stopwatch_start(&stopwatch)

                delta_time := f32(time.duration_seconds(delta_duration))

                // If the game's framerate drops below 30fps, clamp the delta_time to avoid unexpected game logic.
                // At these framerates the game's logic will run slower than realtime. Adjust the max delta_time as required.
                delta_time = math.min(delta_time, 1/30.0)

                msg: win.MSG
                for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
                        if msg.message == win.WM_QUIT {
                                is_running = false
                        }
                        win.TranslateMessage(&msg)
                        win.DispatchMessageW(&msg)
                }

                if did_resize {
                        device_context->OMSetRenderTargets(0, nil, nil)
                        framebuffer_view->Release()
                       
                        res := swapchain->ResizeBuffers(0, 0, 0, .UNKNOWN, {})
                        assert_messagebox(res, "Swapchain buffer resize failed")

                        framebuffer: ^d3d11.ITexture2D
                        res  = swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&framebuffer))
                        assert_messagebox(res, "Get framebuffer failed")
                        defer framebuffer->Release()

                        res  = device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view)
                        assert_messagebox(res, "Create RenderTargetView failed")

                        did_resize = false
                }

                // Update game data
                triangle_spin += triangle_spin_rate * delta_time

                // Upload constants
                mapped_constant_buffer: d3d11.MAPPED_SUBRESOURCE
                map_res := device_context->Map(constant_buffer, 0, .WRITE_DISCARD, {}, &mapped_constant_buffer)

                constants := (^Constants)(mapped_constant_buffer.pData)
                constants^ = Constants {
                        position = [2]f32{math.cos(triangle_spin), math.sin(triangle_spin)} * 0.3,
                        color    = {0.7, 0.65, 0.1, 1},
                }

                device_context->Unmap(constant_buffer, 0)


                bg_color := [4]f32 {0.3, 0.4, 0.6, 1}
                device_context->ClearRenderTargetView(framebuffer_view, &bg_color)

                window_rect: win.RECT
                win.GetClientRect(hWnd, &window_rect)
                viewport := d3d11.VIEWPORT {
                        TopLeftX = 0,
                        TopLeftY = 0,
                        Width    = f32(window_rect.right - window_rect.left),
                        Height   = f32(window_rect.bottom - window_rect.top),
                        MinDepth = 0,
                        MaxDepth = 1,
                }

                device_context->RSSetViewports(1, &viewport)
                device_context->OMSetRenderTargets(1, &framebuffer_view, nil)

                device_context->IASetPrimitiveTopology(.TRIANGLELIST)
                device_context->IASetInputLayout(input_layout)

                device_context->VSSetShader(vertex_shader, nil, 0)
                device_context->PSSetShader(pixel_shader, nil, 0)

                device_context->VSSetConstantBuffers(0, 1, &constant_buffer)
                device_context->IASetVertexBuffers(0, 1, &vertex_buffer, &vertex_stride, &vertex_offset)

                device_context->Draw(vertex_count, 0)

                swapchain->Present(1, {})
        }
}
