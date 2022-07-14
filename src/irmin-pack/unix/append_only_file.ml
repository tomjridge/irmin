(*
 * Copyright (c) 2022-2022 Tarides <contact@tarides.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Import
include Append_only_file_intf

module Make (Io : Io.S) = struct
  module Io = Io

  type rw_perm = {
    buf : Buffer.t;
    auto_flush_threshold : int;
    auto_flush_callback : unit -> unit;
  }
  (** [rw_perm] contains the data necessary to operate in readwrite mode. *)

  type t = {
    io : Io.t;
    mutable persisted_end_offset : int63;
    (* NOTE the [persisted_end_offset] is "modulo" the [dead_header_size]: the real offset
       in the file will be [persisted_end_offset+dead_header_size] *)
    dead_header_size : int63;
    rw_perm : rw_perm option;
  }

  let create_rw ~path ~overwrite ~auto_flush_threshold ~auto_flush_callback =
    let open Result_syntax in
    let+ io = Io.create ~path ~overwrite in
    let persisted_end_offset = Int63.zero in
    let buf = Buffer.create 0 in
    {
      io;
      persisted_end_offset;
      dead_header_size = Int63.zero;
      rw_perm = Some { buf; auto_flush_threshold; auto_flush_callback };
    }

  let open_rw ~path ~end_offset ~dead_header_size ~auto_flush_threshold
      ~auto_flush_callback =
    let open Result_syntax in
    let+ io = Io.open_ ~path ~readonly:false in
    let persisted_end_offset = end_offset in
    let dead_header_size = Int63.of_int dead_header_size in
    let buf = Buffer.create 0 in
    {
      io;
      persisted_end_offset;
      dead_header_size;
      rw_perm = Some { buf; auto_flush_threshold; auto_flush_callback };
    }

  let open_ro ~path ~end_offset ~dead_header_size =
    let open Result_syntax in
    let+ io = Io.open_ ~path ~readonly:true in
    let persisted_end_offset = end_offset in
    let dead_header_size = Int63.of_int dead_header_size in
    { io; persisted_end_offset; dead_header_size; rw_perm = None }

  let empty_buffer = function
    | { rw_perm = Some { buf; _ }; _ } when Buffer.length buf > 0 -> false
    | _ -> true

  let close t =
    if not @@ empty_buffer t then Error `Pending_flush else Io.close t.io

  let readonly t = Io.readonly t.io
  let path t = Io.path t.io

  let auto_flush_threshold = function
    | { rw_perm = None; _ } -> None
    | { rw_perm = Some rw_perm; _ } -> Some rw_perm.auto_flush_threshold

  (* NOTE [end_offset] (rw-only function) includes *unwritten* bytes in the write buffer;
     these bytes are *not* persisted on disk; however, [refresh_end_offset] takes a
     [new_end_offset] that presumably must come from calling [end_offset]; for this to be
     valid, we should call flush on the RW instance, then call end_offset, before calling
     refresh_end_offset *)

  let end_offset t =
    match t.rw_perm with
    | None -> t.persisted_end_offset
    | Some rw_perm ->
        let open Int63.Syntax in
        t.persisted_end_offset + (Buffer.length rw_perm.buf |> Int63.of_int)

  let refresh_end_offset t new_end_offset =
    match t.rw_perm with
    | Some _ -> Error `Rw_not_allowed
    | None ->
        t.persisted_end_offset <- new_end_offset;
        Ok ()

  let flush t =
    match t.rw_perm with
    | None -> Error `Ro_not_allowed
    | Some rw_perm ->
        let open Result_syntax in
        let open Int63.Syntax in
        let s = Buffer.contents rw_perm.buf in
        let off = t.persisted_end_offset + t.dead_header_size in
        (* NOTE in this module, before *any* Io.{read,write}, the [dead_header_size] is
           added to the offset; effectively this means that the initial bytes in the file
           are ignored, and that we work with addresses that are "short by
           dead_header_size"/ For example, the actual file size on disk after flush will
           be longer (by [dead_header_size] bytes) compared to the [end_offset] *)
        let+ () = Io.write_string t.io ~off s in
        t.persisted_end_offset <-
          t.persisted_end_offset + (String.length s |> Int63.of_int);
        (* [truncate] is semantically identical to [clear], except that
           [truncate] doesn't deallocate the internal buffer. We use
           [clear] in legacy_io. *)
        Buffer.truncate rw_perm.buf 0

  let fsync t = Io.fsync t.io

  let read_exn t ~off ~len b =
    let open Int63.Syntax in
    let off' = off + Int63.of_int len in
    if off' > t.persisted_end_offset then
      raise (Errors.Pack_error `Read_out_of_bounds);
    let off = off + t.dead_header_size in
    Io.read_exn t.io ~off ~len b

  let read_to_string t ~off ~len =
    let open Int63.Syntax in
    let off' = off + Int63.of_int len in
    if off' > t.persisted_end_offset then Error `Read_out_of_bounds
    else
      let off = off + t.dead_header_size in
      Io.read_to_string t.io ~off ~len

  let append_exn t s =
    match t.rw_perm with
    | None -> raise Errors.RO_not_allowed
    | Some rw_perm ->
        assert (Buffer.length rw_perm.buf < rw_perm.auto_flush_threshold);
        Buffer.add_string rw_perm.buf s;
        if Buffer.length rw_perm.buf >= rw_perm.auto_flush_threshold then (
          rw_perm.auto_flush_callback ();
          assert (empty_buffer t))
end
