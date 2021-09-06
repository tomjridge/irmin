(*
 * Copyright (c) 2018-2021 Tarides <contact@tarides.com>
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
include Pack_index_intf

[@@@warning "-27-32"]
  

module Make (K : Irmin.Hash.S) = struct
  module Key = struct
    type t = K.t
    [@@deriving irmin ~short_hash ~equal ~to_bin_string ~decode_bin]

    let hash = short_hash ?seed:None
    let hash_size = 30
    let encode = to_bin_string
    let encoded_size = K.hash_size

    let decode s off =
      let _, v = decode_bin s off in
      v
  end

  type key = Key.t

  module Val = struct
    type t = int63 * int * Pack_value.Kind.t [@@deriving irmin]

    type fmt = int63 * int32 * Pack_value.Kind.t
    [@@deriving irmin ~to_bin_string ~decode_bin]

    let encode (off, len, kind) = fmt_to_bin_string (off, Int32.of_int len, kind)

    let decode s off =
      let off, len, kind = snd (decode_bin_fmt s off) in
      (off, Int32.to_int len, kind)

    let encoded_size = (64 / 8) + (32 / 8) + 1
  end

  type value = Val.t

  module Btree_stats = Btree.Index.Stats
  module Index_stats = Index.Stats

  (* module Index = Btree.Index.Make (Key) (Val)  *)
  (* include Index *)

  module Limits = struct
    let max_k_size = 40 (* FIXME *)
    let max_v_size = 8 + 4 + 2
  end
  open Limits

  module Btree_ = Mini_btree.Examples.Example_string_string_mmap(Limits)

  (* write through cache, unbounded *)
  type t = { tree:Btree_.t; cache: (Key.t,Val.t option)Hashtbl.t }

  (** Implicit caching of Index instances. TODO: Require the user to pass Pack
      instance caches explicitly. See
      https://github.com/mirage/irmin/issues/1017. *)
  (* let cache = Index.empty_cache () *)

  let v :
    ?flush_callback:(unit -> unit) ->
    ?fresh:bool ->
    ?readonly:bool ->
    ?throttle:[ `Block_writes | `Overcommit_memory ] ->
    log_size:int ->
    string ->
    t
    = fun ?flush_callback ?fresh:(fresh=false) ?readonly:(readonly=false) ?throttle ~log_size fn ->
      Printf.printf "%s: v called with fn %s\n" __LOC__ fn;
      (* fn is actually the name of a directory .../store; so we store the actual data in btree.t *)
      let fn = fn ^"/" ^ "btree.t" in
      ignore(fresh);
      ignore(readonly);
      begin fn |> Filename.dirname |> (fun d -> Sys.command ("mkdir -p "^d)) |> fun i -> ignore i end; (* FIXME fragile *) 
      Btree_.create ~fn |> fun tree -> 
      {tree; cache=Hashtbl.create 1000 }

  let find t k0 = 
    Hashtbl.find_opt t.cache k0 |> function
    | Some v -> v
    | None -> 
      (* FIXME what is the difference between encode and to_bin_string? *)
      let k = Key.to_bin_string k0 in
      assert(String.length k <= max_k_size);
      Btree_.find t.tree k |> function
      | None -> 
        Hashtbl.replace t.cache k0 None; None
      | Some v -> 
        let v = Val.decode v 0 in
        Hashtbl.replace t.cache k0 (Some v);
        Some v

  let add ?overcommit t k0 v = 
    Hashtbl.replace t.cache k0 (Some v);
    let k = Key.to_bin_string k0 in
    v |> Val.encode |> fun v -> 
    assert(String.length k <= max_k_size);
    assert(String.length v <= max_v_size);
    Btree_.insert t.tree k v

  let close t = Btree_.close t.tree

  let merge _t = ()
  let iter _f _t = failwith __LOC__
  let clear _t = failwith __LOC__
  let try_merge _t = ()
  let flush : ?no_callback:unit -> ?with_fsync:bool -> t -> unit = 
    fun ?no_callback ?with_fsync _t -> 
    () (* FIXME add btree.flush *)

  let filter _t _f = failwith __LOC__
  let mem t k = find t k <> None
  let sync _t = ()                                    
end
