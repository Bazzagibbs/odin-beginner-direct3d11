package win_helpers

import win "core:sys/windows"
import "base:intrinsics"
import "core:os"
import "core:fmt"


// If the assertion fails, display a Windows error dialog box and exit with the error code.
// If hresult is a failure, gets the error message and prints to stderr.
assert_messagebox :: proc {
        assert_messagebox_hresult,
        assert_messagebox_generic,
}

assert_messagebox_hresult :: #force_inline proc (hResult: win.HRESULT, message_args: ..any, loc := #caller_location) {
        when !ODIN_DISABLE_ASSERT {
                if hResult < 0 {
                        message := fmt.tprint(..message_args)
                        win.MessageBoxW(nil, win.utf8_to_wstring(message), win.L("Fatal Error"), win.MB_ICONERROR | win.MB_OK)
                        fmt.eprintfln("%v: %v: %s", loc, message, parse_hresult(hResult))
                        intrinsics.debug_trap()
                        os.exit(int(win.GetLastError()))
                }
        }
}

assert_messagebox_generic :: #force_inline proc (assertion: bool, message_args: ..any, loc := #caller_location) {
        when !ODIN_DISABLE_ASSERT {
                if !assertion {
                        message := fmt.tprint(..message_args)
                        win.MessageBoxW(nil, win.utf8_to_wstring(message), win.L("Fatal Error"), win.MB_OK)
                        fmt.eprintfln("%v: %v", loc, message)
                        intrinsics.debug_trap()
                        os.exit(int(win.GetLastError()))
                }
        }
}

// Produce a human-readable utf-16 string from the provided HRESULT.
// Allocates using the provided allocator.
parse_hresult :: #force_inline proc (hResult: win.HRESULT, allocator := context.temp_allocator) -> string {
        buf: [^]u16

        msg_len := win.FormatMessageW(
                flags   =  win.FORMAT_MESSAGE_FROM_SYSTEM | win.FORMAT_MESSAGE_IGNORE_INSERTS | win.FORMAT_MESSAGE_ALLOCATE_BUFFER,
                lpSrc   =  nil,
                msgId   =  u32(hResult),
                langId  =  0,
                buf     =  (win.LPWSTR)(&buf),
                nsize   =  0,
                args    =  nil
        )

        out_str, _ := win.utf16_to_utf8(buf[:msg_len], allocator)
        win.LocalFree(buf)

        return out_str
}


Matrix3_Padded :: struct {
        col_0: [4]f32,
        col_1: [4]f32,
        col_2: [3]f32, // a single 32-bit element can fit in the last element instead of padding
}

pad_matrix3 :: #force_inline proc "contextless" (mat: matrix[3,3]f32) -> Matrix3_Padded {
        return Matrix3_Padded {
                col_0 = {mat[0].x, mat[0].y, mat[0].z, 0},
                col_1 = {mat[1].x, mat[1].y, mat[1].z, 0},
                col_2 = mat[2],
        }
}
