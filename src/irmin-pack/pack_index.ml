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

  type t = (K.t, Val.t) Hashtbl.t

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
      Hashtbl.create 1000

  let find t k = 
    (* FIXME what is the difference between encode and to_bin_string? *)
    Hashtbl.find_opt t k
      
  let add ?overcommit t k v = 
    Hashtbl.replace t k v

  let close t = ()
    

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
