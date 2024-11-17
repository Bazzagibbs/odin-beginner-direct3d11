package d3d11_demo

import "core:strconv"
import "core:bufio"
import "core:io"
import "core:strings"
import "core:text/scanner"
import "core:math"
import "core:math/linalg"
import "core:bytes"

import "core:fmt"


Mesh_Data :: struct {
        vertex_buffer: [dynamic]Vertex_Data,
        index_buffer : [dynamic]u32,
}

Vertex_Data :: struct #packed {
        position : [3]f32,
        tex_coord : [2]f32,
        normal : [3]f32,
}

Face_Index :: struct {
        position  : int,
        tex_coord : int,
        normal    : int,
}


/*
        This is not a complete .obj parser.
        The Wavefront .obj spec is available at http://www.martinreddy.net/gfx/3d/OBJ.spec

        This implementation enforces the following limitations on statements:
        - backslash-newline is ignored
        - `v` Geometric vertices `v x y z [w] [r g b]`
                - Optional fields (w, r, g, b) are discarded
        - `vt` Texture coordinates `vt x [y [z]]`
                - Default y = 0 if missing
                - Discard z
        - `vn` Vertex normals `vn x y z`
                - Parsed normals will be normalized (not enforced by spec)
        - `f` Face `f apos/atex/anorm bpos/btex/bnorm cpos/ctex/cnorm`
                - Negative indices are not supported
        
        All other statements are discarded.
*/
wavefront_load :: proc (file_data: string, flip_texture_v := true, allocator := context.allocator) -> (mesh_data: Mesh_Data, ok: bool) {
       
        mesh_data = Mesh_Data {
                vertex_buffer = make([dynamic]Vertex_Data, allocator),
                index_buffer = make([dynamic]u32, allocator),
        }


        v_buffer := make([dynamic][3]f32, allocator)
        vt_buffer := make([dynamic][2]f32, allocator)
        vn_buffer := make([dynamic][3]f32, allocator)
        defer delete(v_buffer)
        defer delete(vt_buffer)
        defer delete(vn_buffer)

        face_buffer := make([dynamic]Face_Index, allocator)
        defer delete(face_buffer)

        true_indices := make(map[Face_Index]u32, allocator)
        defer delete(true_indices)


        it := file_data
        for line in strings.split_lines_iterator(&it) {

                line_it := line
                statement := strings.split_iterator(&line_it, " ") or_continue

                switch statement {
                case "v":
                        new_v : [3]f32
                        new_v.x, _ = _scan_f32(&line_it)
                        new_v.y, _ = _scan_f32(&line_it)
                        new_v.z, _ = _scan_f32(&line_it)
                        append(&v_buffer, new_v)
                        continue

                case "vt":
                        new_vt : [2]f32
                        new_vt.x, _ = _scan_f32(&line_it)
                        new_vt.y    = _scan_f32(&line_it) or_else 0
                        append(&vt_buffer, new_vt)
                        continue

                case "vn":
                        new_vn : [3]f32
                        new_vn.x, _ = _scan_f32(&line_it)
                        new_vn.y, _ = _scan_f32(&line_it)
                        new_vn.z, _ = _scan_f32(&line_it)
                        append(&vn_buffer, new_vn)
                        continue

                case "f":
                        clear(&face_buffer)
                        for {
                                face_index := _scan_face_index(&line_it) or_break
                                append(&face_buffer, face_index)
                        }

                        first_ti, last_ti: u32

                        for face_index, i in face_buffer {
                                ti, exists := true_indices[face_index]
                                if !exists {
                                        ti = u32(len(mesh_data.vertex_buffer))
                                        true_indices[face_index] = ti
                                        
                                        new_vertex := Vertex_Data {
                                                position  = v_buffer[face_index.position],
                                                tex_coord = vt_buffer[face_index.tex_coord],
                                                normal    = vn_buffer[face_index.normal],
                                        }

                                        if flip_texture_v {
                                                new_vertex.tex_coord.y = 1.0 - new_vertex.tex_coord.y
                                        }

                                        append(&mesh_data.vertex_buffer, new_vertex)
                                }

                                if i == 0 {
                                        first_ti = ti
                                }


                                if i > 2 {
                                        // Create fan for ngons
                                        append(&mesh_data.index_buffer, first_ti)
                                        append(&mesh_data.index_buffer, last_ti)
                                }

                                last_ti = ti

                                append(&mesh_data.index_buffer, ti)
                        }

                        continue

                case:
                        continue
                }
        }

        return mesh_data, true
}


wavefront_destroy :: proc (mesh_data: ^Mesh_Data) {
        delete(mesh_data.vertex_buffer)
        delete(mesh_data.index_buffer)
}


@(private="file")
_scan_f32 :: proc (it: ^string, sep: string = " ") -> (val: f32, ok: bool) {
        val_str := strings.split_iterator(it, sep) or_return
        val = strconv.parse_f32(val_str) or_return
        return val, true
}

@(private="file")
_scan_int :: proc (it: ^string, sep: string = " ") -> (val: int, ok: bool) {
        val_str := strings.split_iterator(it, sep) or_return
        val = strconv.parse_int(val_str) or_return
        return val, true
}


@(private="file")
_scan_face_index :: proc (it: ^string) -> (face_index: Face_Index, ok: bool) {
        elem := strings.split_iterator(it, " ") or_return

        vi    := _scan_int(&elem, "/") or_return
        vti   := _scan_int(&elem, "/") or_else 0
        vni   := _scan_int(&elem, "/") or_else 0

        index := Face_Index {
                position  = vi - 1,
                tex_coord = vti - 1,
                normal    = vni - 1,
        }

        return index, true
}
