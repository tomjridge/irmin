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

module type S = sig
  include Btree.Index.S with type value = int63 * int * Pack_value.Kind.t

  val v :
    ?flush_callback:(unit -> unit) ->
    ?fresh:bool ->
    ?readonly:bool ->
    ?throttle:[ `Block_writes | `Overcommit_memory ] ->
    log_size:int ->
    string ->
    t
  (** Constructor for indices, memoized by [(path, readonly)] pairs. *)

  val find : t -> key -> value option
  val add : ?overcommit:bool -> t -> key -> value -> unit
  val close : t -> unit
  val merge : t -> unit

  module Index_stats = Index.Stats
  module Btree_stats = Btree.Index.Stats
end

module type Sigs = sig
  module type S = S

  module Make (K : Irmin.Hash.S) : S with type key = K.t
end
