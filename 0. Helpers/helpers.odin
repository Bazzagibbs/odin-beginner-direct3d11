package win_helpers

import win "core:sys/windows"
import "base:intrinsics"
import "core:os"
import "core:fmt"

// Windows "DoSomethingW" procs use UTF16 strings.
// This intrinsic defines UTF16 constants.
L :: intrinsics.constant_utf16_cstring


// Some constants in `core:sys/windows` are cstrings, but should be UTF16 strings
as_lstring :: proc "contextless" (cstr: cstring) -> [^]u16 {
        return transmute([^]u16)(cstr)
}


// If the assertion fails, display a Windows error dialog box and exit with the error code.
// If hresult is a failure, gets the error message and prints to stderr.
assert_messagebox :: proc {
        assert_messagebox_hresult,
        assert_messagebox_generic,
}

assert_messagebox_hresult :: #force_inline proc (hResult: win.HRESULT, message: [^]u16, loc := #caller_location) {
        when !ODIN_DISABLE_ASSERT {
                if hResult < 0 {
                        win.MessageBoxW(nil, message, L("Fatal Error"), win.MB_ICONERROR | win.MB_OK)
                        fmt.eprintfln("[WINDOWS] %v %s", loc, parse_hresult(hResult))
                        intrinsics.debug_trap()
                        os.exit(int(win.GetLastError()))
                }
        }
}

assert_messagebox_generic :: #force_inline proc "contextless" (assertion: bool, message: [^]u16) {
        when !ODIN_DISABLE_ASSERT {
                if !assertion {
                        win.MessageBoxW(nil, message, L("Fatal Error"), win.MB_OK)
                        intrinsics.debug_trap()
                        os.exit(int(win.GetLastError()))
                }
        }
}

// Produce a human-readable utf-16 string from the profided HRESULT.
parse_hresult :: #force_inline proc "contextless" (hResult: win.HRESULT) -> []u16 {
        out_str: rawptr

        msg_len := win.FormatMessageW(
                flags = win.FORMAT_MESSAGE_FROM_SYSTEM | win.FORMAT_MESSAGE_IGNORE_INSERTS | win.FORMAT_MESSAGE_ALLOCATE_BUFFER,
                lpSrc = nil,
                msgId = u32(hResult),
                langId = 0,
                buf = (^u16)(&out_str),
                nsize = 0,
                args = nil
        )

        return ([^]u16)(out_str)[:msg_len]
}

// Not sure why this isn't part of `core:slice`. Gets the byte-size of a slice's `data` buffer.
slice_data_size :: #force_inline proc "contextless" (slice: $T/[]$E) -> int {
        return size_of(E) * len(slice)
}
