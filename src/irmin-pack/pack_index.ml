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

  module Btree_stats = Btree.Index.Stats
  module Index_stats = Index.Stats

  module Index = Btree.Index.Make (Key) (Val) 
  include Index

  (** Implicit caching of Index instances. TODO: Require the user to pass Pack
      instance caches explicitly. See
      https://github.com/mirage/irmin/issues/1017. *)
  let cache = Index.empty_cache ()

  let v = Index.v ~cache
  let add ?overcommit t k v = replace ?overcommit t k v
  let find t k = match find t k with exception Not_found -> None | h -> Some h
  let close t = Index.close t
end
