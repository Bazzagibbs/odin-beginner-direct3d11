package d3d11_demo

import helpers "../0. Helpers"
import "base:intrinsics"
import "base:runtime"
import win "core:sys/windows"
import "core:os"
import "core:time"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:bytes"
import "core:mem"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/hlsl"
import "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"

WINDOW_NAME :: "06. Creating a Depth Buffer"

assert_messagebox :: helpers.assert_messagebox
slice_byte_size   :: helpers.slice_byte_size

did_resize : bool

inputs : bit_set[Input_Action]

Input_Action :: enum {
        Unknown,
        Forward,
        Backward,
        Left,
        Right,
        Pitch_Up,
        Pitch_Down,
        Yaw_Left,
        Yaw_Right,
}


virtual_key_to_input_action :: proc "contextless" (vkey: win.WPARAM) -> Input_Action {
        switch vkey {
        case win.VK_W:
                return .Forward
        case win.VK_S:
                return .Backward
        case win.VK_A:
                return .Left
        case win.VK_D:
                return .Right
        case win.VK_UP:
                return .Pitch_Up
        case win.VK_DOWN:
                return .Pitch_Down
        case win.VK_LEFT:
                return .Yaw_Left
        case win.VK_RIGHT:
                return .Yaw_Right
        case:
                return .Unknown
        }
}


render_target_init :: proc (device: ^d3d11.IDevice, swapchain: ^dxgi.ISwapChain1) -> (framebuffer_view: ^d3d11.IRenderTargetView, depth_buffer_view: ^d3d11.IDepthStencilView) {
        // Framebuffer
        framebuffer: ^d3d11.ITexture2D
        res := swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&framebuffer))
        assert_messagebox(res, "Get Framebuffer failed")
        defer framebuffer->Release()

        res  = device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view)
        assert_messagebox(res, "CreateRenderTargetView failed")

        // Depth buffer
        depth_buffer_desc : d3d11.TEXTURE2D_DESC
        framebuffer->GetDesc(&depth_buffer_desc)

        depth_buffer_desc.Format    = .D24_UNORM_S8_UINT
        depth_buffer_desc.BindFlags = {.DEPTH_STENCIL}

        depth_buffer : ^d3d11.ITexture2D
        res = device->CreateTexture2D(&depth_buffer_desc, nil, &depth_buffer)
        assert_messagebox(res, "Create DepthBuffer failed")
        defer depth_buffer->Release()

        device->CreateDepthStencilView(depth_buffer, nil, &depth_buffer_view)
        return
}


// A perspective projection matrix where the clip space is x, y [-1, 1] and depth is 0 = near, 1 = far.
// We can't use `linalg.matrix4_perspective()` as it uses OpenGL clip space (depth [-1, 1]).
matrix_perspective_01 :: proc (fovy, aspect, near, far: f32) -> matrix[4,4]f32 {
        y_scale       := 1 / math.tan(fovy * 0.5)
        x_scale       := y_scale / aspect
        z_scale       := far / (far - near)
        z_translation := -near * z_scale

        return matrix[4,4]f32 {
                x_scale, 0, 0, 0,
                0, y_scale, 0, 0,
                0, 0, z_scale, z_translation,
                0, 0, 1, 0
        }
}


wnd_proc :: proc "stdcall" (hWnd: win.HWND, uMsg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) -> (result: win.LRESULT) {
        result = 0

        switch uMsg {
        case win.WM_KEYDOWN: 
                if wParam == win.VK_ESCAPE {
                        win.DestroyWindow(hWnd)
                        return
                }
                input_action := virtual_key_to_input_action(wParam)
                inputs += {input_action}

        case win.WM_KEYUP:
                input_action := virtual_key_to_input_action(wParam)
                inputs -= {input_action}

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


        // Create Framebuffer Render Target and Depth buffer
        framebuffer_view: ^d3d11.IRenderTargetView
        depth_buffer_view: ^d3d11.IDepthStencilView
        
        framebuffer_view, depth_buffer_view = render_target_init(device, swapchain)

        defer framebuffer_view->Release()
        defer depth_buffer_view->Release()


        depth_stencil_state : ^d3d11.IDepthStencilState
        {
                depth_stencil_desc := d3d11.DEPTH_STENCIL_DESC {
                        DepthEnable    = true,
                        DepthWriteMask = .ALL,
                        DepthFunc      = .LESS,
                }

                device->CreateDepthStencilState(&depth_stencil_desc, &depth_stencil_state)
        }
        defer depth_stencil_state->Release()


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
                                fmt.eprintfln("HLSL Compile error: %s", cstring(error_str))
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
                        assert_messagebox(res, "Vertex shader compilation failed")
                }

                res = device->CreatePixelShader(
                        pShaderBytecode = pixel_shader_blob->GetBufferPointer(),
                        BytecodeLength  = pixel_shader_blob->GetBufferSize(),
                        pClassLinkage   = nil,
                        ppPixelShader   = &pixel_shader
                )
                assert_messagebox(res, "Vertex shader creation failed")
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
                        {
                                SemanticName         = "tex_coord",
                                SemanticIndex        = 0,
                                Format               = .R32G32_FLOAT,
                                InputSlot            = 0,
                                AlignedByteOffset    = d3d11.APPEND_ALIGNED_ELEMENT,
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
                vertex_data := []f32 {          // clockwise winding
                //      x,    y,        u, v
                        -0.5,  0.5,     0, 0,   // top left
                         0.5, -0.5,     1, 1,   // bottom right
                        -0.5, -0.5,     0, 1,   // bottom left
                        -0.5,  0.5,     0, 0,   // top left
                         0.5,  0.5,     1, 0,   // top right
                         0.5, -0.5,     1, 1,   // bottom right
                }
                vertex_stride = size_of(f32) * 4
                vertex_count  = u32(len(vertex_data) / 4)
                vertex_offset = 0

                vertex_buffer_desc := d3d11.BUFFER_DESC {
                        ByteWidth = u32(slice_byte_size(vertex_data)),
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


        // Create sampler state
        sampler: ^d3d11.ISamplerState
        {
                sampler_desc := d3d11.SAMPLER_DESC {
                        Filter         = .MIN_MAG_MIP_POINT,
                        AddressU       = .BORDER,
                        AddressV       = .BORDER,
                        AddressW       = .BORDER,
                        ComparisonFunc = .NEVER,
                        BorderColor    = {1, 1, 1, 0},
                }

                res := device->CreateSamplerState(&sampler_desc, &sampler)
                assert_messagebox(res, "Create SamplerState failed")
        }


        // Load texture
        texture: ^d3d11.ITexture2D
        texture_view: ^d3d11.IShaderResourceView
        {
                img, err := image.load_from_bytes(#load("texture.png"))
                assert_messagebox(err == nil, "Failed to load image")
                defer image.destroy(img)

                image.alpha_add_if_missing(img)
                assert_messagebox(img.depth == 8 && img.channels == 4, "Image is not RGBA8")
                img_data := bytes.buffer_to_bytes(&img.pixels)

                texture_desc := d3d11.TEXTURE2D_DESC {
                        Width     = u32(img.width),
                        Height    = u32(img.height),
                        MipLevels = 1,
                        ArraySize = 1,
                        Format    = .R8G8B8A8_UNORM_SRGB,
                        Usage     = .IMMUTABLE,
                        BindFlags = {.SHADER_RESOURCE},
                        SampleDesc = { Count = 1 },
                }

                img_bytes_per_row := u32(img.width) * 4

                subresource_data := d3d11.SUBRESOURCE_DATA {
                        pSysMem     = raw_data(img_data),
                        SysMemPitch = img_bytes_per_row,
                }

                res := device->CreateTexture2D(&texture_desc, &subresource_data, &texture)
                assert_messagebox(res, "CreateTexture2D failed")

                res  = device->CreateShaderResourceView(texture, nil, &texture_view)
                assert_messagebox(res, "Create texture view failed")
        }
        defer texture->Release()
        defer texture_view->Release()
       
        
        Constants :: struct #align(16) {
                model_view_projection  : matrix[4,4]f32,
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
        quad_front_model_matrix := linalg.matrix4_translate([3]f32{0.2, -0.2, 0})
        quad_back_model_matrix  := linalg.matrix4_translate([3]f32{-0.2, 0.2, 0.5})

        cam_position := [3]f32 {0, 0, -2}
        cam_rotation := [2]f32 {0, 0}

        cam_move_speed : f32 = 2
        cam_pitch_speed : f32 = math.PI / 2   // full pitch range per two seconds. Pitch clamped to +-90 deg
        cam_yaw_speed : f32 = math.TAU / 8    // full yaw range per eight seconds

        stopwatch : time.Stopwatch
        time.stopwatch_start(&stopwatch)

        is_running := true
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
                        depth_buffer_view->Release()

                        res := swapchain->ResizeBuffers(0, 0, 0, .UNKNOWN, {})
                        assert_messagebox(res, "Swapchain buffer resize failed")

                        framebuffer_view, depth_buffer_view = render_target_init(device, swapchain)
                        did_resize = false
                }

                // Update game data
                delta_position: [2]f32
                delta_rotation: [2]f32

                if Input_Action.Forward in inputs {
                        delta_position += {0, 1}
                }
                if Input_Action.Backward in inputs {
                        delta_position += {0, -1}
                }
                if Input_Action.Left in inputs {
                        delta_position += {-1, 0}
                }
                if Input_Action.Right in inputs {
                        delta_position += {1, 0}
                }

                if Input_Action.Pitch_Up in inputs {
                        delta_rotation += {-1, 0}
                }
                if Input_Action.Pitch_Down in inputs {
                        delta_rotation += {1, 0}
                }
                if Input_Action.Yaw_Left in inputs {
                        delta_rotation += {0, -1}
                }
                if Input_Action.Yaw_Right in inputs {
                        delta_rotation += {0, 1}
                }

                delta_position = linalg.normalize0(delta_position)

                cam_rotation.x += delta_rotation.x * (cam_pitch_speed * delta_time)
                cam_rotation.x = math.clamp(cam_rotation.x, -math.PI/2, math.PI/2)
                cam_rotation.y += delta_rotation.y * (cam_yaw_speed * delta_time)


                // Rotate position input by the camera's yaw
                input_rotation := linalg.matrix2_rotate(cam_rotation.y)
                delta_position_world := (delta_position * input_rotation) * (cam_move_speed * delta_time)
                cam_position += [3]f32{delta_position_world.x, 0, delta_position_world.y}

                // View matrix (world-space to camera-space)
                view_translate_matrix := linalg.matrix4_translate(cam_position)
                view_rotate_matrix := linalg.matrix4_from_yaw_pitch_roll(cam_rotation.y, cam_rotation.x, 0)
                view_matrix := linalg.inverse(view_translate_matrix * view_rotate_matrix)

                bg_color := [4]f32 {0, 0.4, 0.6, 1}
                device_context->ClearRenderTargetView(framebuffer_view, &bg_color)
                device_context->ClearDepthStencilView(depth_buffer_view, {.DEPTH}, 1, 0)

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

                projection_matrix := matrix_perspective_01(
                        fovy   = 60 * math.RAD_PER_DEG,
                        aspect = viewport.Width / viewport.Height,
                        near   = 0.01,
                        far    = 1000
                )

                device_context->RSSetViewports(1, &viewport)
                device_context->OMSetRenderTargets(1, &framebuffer_view, depth_buffer_view)
                device_context->OMSetDepthStencilState(depth_stencil_state, 0)

                device_context->IASetPrimitiveTopology(.TRIANGLELIST)
                device_context->IASetInputLayout(input_layout)

                device_context->VSSetShader(vertex_shader, nil, 0)
                device_context->PSSetShader(pixel_shader, nil, 0)
                
                device_context->PSSetSamplers(0, 1, &sampler)
                device_context->IASetVertexBuffers(0, 1, &vertex_buffer, &vertex_stride, &vertex_offset)

                device_context->PSSetShaderResources(0, 1, &texture_view)

                mapped_constant_buffer : d3d11.MAPPED_SUBRESOURCE

                // Front quad
                front_quad_constants := Constants { model_view_projection = projection_matrix * view_matrix * quad_front_model_matrix } // bottom right
                device_context->Map(constant_buffer, 0, .WRITE_DISCARD, {}, &mapped_constant_buffer)
                mem.copy(mapped_constant_buffer.pData, &front_quad_constants, size_of(Constants))
                device_context->Unmap(constant_buffer, 0)
                
                device_context->VSSetConstantBuffers(0, 1, &constant_buffer)
                device_context->Draw(vertex_count, 0)

                // Back quad
                back_quad_constants := Constants { model_view_projection = projection_matrix * view_matrix * quad_back_model_matrix } // top left
                device_context->Map(constant_buffer, 0, .WRITE_DISCARD, {}, &mapped_constant_buffer)
                mem.copy(mapped_constant_buffer.pData, &back_quad_constants, size_of(Constants))
                device_context->Unmap(constant_buffer, 0)

                device_context->VSSetConstantBuffers(0, 1, &constant_buffer)
                device_context->Draw(vertex_count, 0)
                
                swapchain->Present(1, {})
        }
}
