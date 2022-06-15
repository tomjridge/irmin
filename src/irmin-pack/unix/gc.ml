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

open! Import

let buffer_size = 8192

module Make
    (Fm : File_manager.S)
    (Dict : Dict.S with type file_manager = Fm.t) (Commit_value : sig
      type t
      type hash
      type node_key = hash Irmin_pack.Pack_key.t
      type commit_key = node_key

      val node : t -> node_key
    end)
    (Commit_store : Pack_store.S
                      with type value = Commit_value.t
                       and type key = Commit_value.commit_key
                       and type file_manager = Fm.t
                       and type dict = Dict.t
                       and type hash = Commit_value.hash)
    (Node_value : sig
      type t
      type key = Commit_value.commit_key
      type step

      val pred :
        t ->
        (step option * [ `Contents of key | `Inode of key | `Node of key ]) list
    end)
    (Node_store : sig
      type 'a t
      type value
      type key
      type file_manager
      type dict

      val v :
        config:Irmin.Backend.Conf.t -> fm:file_manager -> dict:dict -> read t

      val unsafe_find :
        check_integrity:bool -> [< read ] t -> key -> value option
    end
    with type value = Node_value.t
     and type key = Commit_value.commit_key
     and type file_manager = Fm.t
     and type dict = Dict.t) =
struct
  type key = Commit_value.commit_key
  type kinded_key = [ `Commit of key | `Inode of key | `Contents of key ]

  type abort_error =
    [ `Node_or_contents_key_is_indexed of key | `Dangling_key of key ]

  exception Abort_gc of abort_error

  module Io = Fm.Io

  let rec iter_keys node_key node_store ~f =
    match Node_store.unsafe_find ~check_integrity:false node_store node_key with
    | None -> raise (Abort_gc (`Dangling_key node_key))
    | Some node ->
        List.iter
          (fun (_step, kinded_key) ->
            match kinded_key with
            | `Contents key -> f key
            | `Inode key | `Node key ->
                f key;
                iter_keys key node_store ~f)
          (Node_value.pred node)

  let iter_keys :
      Commit_store.key ->
      read Commit_store.t ->
      read Node_store.t ->
      f:(key -> unit) ->
      unit =
   fun commit_key commit_store node_store ~f ->
    f commit_key;
    match
      Commit_store.unsafe_find ~check_integrity:false commit_store commit_key
    with
    | None -> raise (Abort_gc (`Dangling_key commit_key))
    | Some commit ->
        let node_key = Commit_value.node commit in
        f node_key;
        iter_keys node_key node_store ~f

  let init_file ~io ~count =
    let open Result_syntax in
    let char = 'd' (* TODO *) in
    let buffer = String.make buffer_size char in
    let buffer_size = Int63.of_int buffer_size in
    let rec aux off count =
      let ( < ) a b = Int63.compare a b < 0 in
      let ( - ) = Int63.sub in
      let ( + ) = Int63.add in
      let ( === ) = Int63.equal in
      if count === Int63.zero then Ok ()
      else if count < buffer_size then
        let buffer = String.make (Int63.to_int count) char in
        Io.write_string io ~off buffer
      else
        let* () = Io.write_string io ~off buffer in
        let off = off + buffer_size in
        let count = count - buffer_size in
        aux off count
    in
    aux Int63.zero count

  let run config commit_key =
    (* TODO: From ext. Make sure that no batch is ongoing. *)
    let open Result_syntax in
    let root = Irmin_pack.Conf.root config in
    let config =
      Irmin_pack.Conf.init ~fresh:false ~readonly:true ~lru_size:0
        (* ~index_log_size *)
        (* ~merge_throttle *)
        (* ~indexing_strategy *)
        (* ~use_fsync *)
        (* dict_auto_flush_threshold *)
        (* suffix_auto_flush_threshold *)
        root
    in
    let* fm = Fm.open_ro config in
    let dict =
      let capacity = 100_000 in
      Dict.v ~capacity fm
    in
    let node_store = Node_store.v ~config ~fm ~dict in
    let commit_store = Commit_store.v ~config ~fm ~dict in

    let pl : Control_file.Latest_payload.t =
      Fm.Control.payload (Fm.control fm)
    in
    let* generation =
      match pl.status with
      | From_v1_v2_post_upgrade _ -> Error `Gc_disallowed
      | From_v3_gc_disallowed -> assert false
      | From_v3_gc_allowed x -> Ok (x.generation + 1)
    in

    (* Load the commit key if necessary *)
    let* commit_key =
      let state : _ Irmin_pack.Pack_key.state =
        Irmin_pack.Pack_key.inspect commit_key
      in
      match state with
      | Direct _ -> Ok commit_key
      | Indexed h -> (
          match Commit_store.index_direct_with_kind commit_store h with
          | None -> Error `Commit_key_is_indexed_and_dangling
          | Some (k, _kind) -> Ok k)
    in

    let suffix_path = Irmin_pack.Layout.V3.suffix ~root ~generation in
    let suffix_size = pl.entry_offset_suffix_end in
    let* dst_io = Io.create ~path:suffix_path ~overwrite:false in
    let src_ao = Fm.suffix fm in
    let* () = init_file ~io:dst_io ~count:suffix_size in

    let buffer = Bytes.create buffer_size in
    let rec transfer off len_remaining =
      let len = min buffer_size len_remaining in
      Fm.Suffix.read_exn src_ao ~off ~len buffer;
      Io.write_exn dst_io ~off ~len (Bytes.unsafe_to_string buffer);
      let len_remaining = len - buffer_size in
      if len_remaining > 0 then
        transfer Int63.(add off (of_int len)) len_remaining
    in

    let f key =
      let state : _ Irmin_pack.Pack_key.state =
        Irmin_pack.Pack_key.inspect key
      in
      match state with
      | Indexed _ -> raise (Abort_gc (`Node_or_contents_key_is_indexed key))
      | Direct { offset; length; _ } -> transfer offset length
    in
    let* () =
      try
        iter_keys commit_key commit_store node_store ~f;
        Ok ()
      with Abort_gc (#abort_error as err) -> Error err
    in

    let* () = Io.close dst_io in
    let* () = Fm.close fm in

    Ok generation
end
