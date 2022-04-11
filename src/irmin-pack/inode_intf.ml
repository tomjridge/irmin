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

module type Child_ordering = sig
  type step
  type key

  (* step is just a simple name; key is something that can be used in index following; idea is to compute "key" upfront then use repeatedly as we descend tree *)
  val key : step -> key
  val index : depth:int -> key -> int
end

module type Snapshot = sig
  type hash
  type metadata

  type kinded_hash = Contents of hash * metadata | Node of hash
  [@@deriving irmin]

  type entry = { step : string; hash : kinded_hash } [@@deriving irmin]

  type inode_tree = { depth : int; length : int; pointers : (int * hash) list }
  [@@deriving irmin]

  type v = Inode_tree of inode_tree | Inode_value of entry list
  [@@deriving irmin]

  type inode = { v : v; root : bool } [@@deriving irmin]
end

(* value here is presumably Node, given the include below (or maybe an
   inode, if inode implements the same intf); so the inode maps a
   pack_key to a node *)
module type Value = sig
  type key (* will be Pack_key *)

  (* all the functions we expect of a node; NOTE introduces type t *)
  include
    Irmin.Node.Generic_key.S
      with type node_key = key  (* pointer to children either node_key or contents_key *)
       and type contents_key = key

  (* predecessor of a Node is... ?? where defined? likely this is predecessor of an inode? *)
  val pred :
    t ->
    (step option
    * [ `Node of node_key | `Inode of node_key | `Contents of contents_key ])
    list

  (* as Irmin.Node.Generic_key.S ... but Irmin.Node_intf.Portable has
     already set contents_keys and node_key to hash, not keys.

     once we have a t (from above Generic_key.S) , we can convert to a
     Portable t, where all the child pointers are hashes; conversions happens via Portable.S of_node function *)
  module Portable :
    Irmin.Node.Portable.S
      with type node := t
       and type hash = hash
       and type step := step
       and type metadata := metadata

  val nb_children : t -> int (* no. of children of an inode?? yes *)
end

(* ?? a raw... pack value? *)
module type Raw = sig
  include Pack_value.S

  val depth : t -> int option (* ?? *)

  exception Invalid_depth of { expected : int; got : int; v : t } (* ?? *)

  val decode_children_offsets : (* ?? *)
    entry_of_offset:(int63 -> 'a) ->
    entry_of_hash:(hash -> 'a) ->
    string ->
    int ref ->
    'a list
end

(* main interface to inodes *)
module type S = sig
  include Irmin.Indexable.S
  module Hash : Irmin.Hash.S with type t = hash

  module Val :
    Value
      with type t = value
       and type key = key
       and type hash = Hash.t
       and type Portable.hash := hash

  val decode_bin_length : string -> int -> int
  val integrity_check_inodes : [ `Read ] t -> key -> (unit, string) result Lwt.t
  val save : ?allow_non_root:bool -> 'a t -> value -> key
end

(* as S, but using irmin-pack persistent backend *)
module type Persistent = sig
  include S

  type index

  val v :
    ?fresh:bool ->
    ?readonly:bool ->
    ?lru_size:int ->
    index:index ->
    indexing_strategy:Pack_store.Indexing_strategy.t ->
    string ->
    read t Lwt.t

  include S.Checkable with type 'a t := 'a t and type hash := hash

  val sync : 'a t -> unit
  val clear_caches : 'a t -> unit
  val integrity_check_inodes : [ `Read ] t -> key -> (unit, string) result Lwt.t

  module Pack :
    Pack_store.S
      with type index := index
       and type key := hash Pack_key.t
       and type hash := hash
       and type 'a t = 'a t

  module Raw :
    Raw
      with type t = Pack.value
       and type hash := hash
       and type key := hash Pack_key.t

  module Snapshot :
    Snapshot with type hash = hash and type metadata = Val.metadata

  val to_snapshot : Raw.t -> Snapshot.inode
  val of_snapshot : 'a t -> index:(hash -> key) -> Snapshot.inode -> value
end

(** Unstable internal API agnostic about the underlying storage. Use it only to
    implement or test inodes. *)
module type Internal = sig
  type hash
  type key

  val pp_hash : hash Fmt.t

  module Snapshot : Snapshot with type hash = hash
  module Raw : Raw with type hash = hash and type key = key

  module Val : sig
    include
      Value
        with type hash = hash
         and type key = key
         and type metadata = Snapshot.metadata

    val of_raw : (expected_depth:int -> key -> Raw.t option) -> Raw.t -> t
    val to_raw : t -> Raw.t

    val save :
      ?allow_non_root:bool ->
      add:(hash -> Raw.t -> key) ->
      index:(hash -> key option) ->
      mem:(key -> bool) ->
      t ->
      key

    val stable : t -> bool
    val length : t -> int
    val index : depth:int -> step -> int

    val integrity_check : t -> bool
    (** Checks the integrity of an inode. *)

    module Concrete : sig
      (** {1 Concrete trees} *)

      (** The type for pointer kinds. *)
      type kinded_key =
        | Contents of contents_key
        | Contents_x of metadata * contents_key
        | Node of node_key
      [@@deriving irmin]

      type entry = { name : step; key : kinded_key } [@@deriving irmin]
      (** The type of entries. *)

      type 'a pointer = { index : int; pointer : hash; tree : 'a }
      [@@deriving irmin]
      (** The type for internal pointers between concrete {!tree}s. *)

      type 'a tree = { depth : int; length : int; pointers : 'a pointer list }
      [@@deriving irmin]
      (** The type for trees. *)

      (** The type for concrete trees. *)
      type t = Tree of t tree | Values of entry list | Blinded
      [@@deriving irmin]

      type len := [ `Eq of int | `Ge of int ]

      type error =
        [ `Invalid_hash of hash * hash * t
        | `Invalid_depth of int * int * t
        | `Invalid_length of len * int * t
        | `Duplicated_entries of t
        | `Duplicated_pointers of t
        | `Unsorted_entries of t
        | `Unsorted_pointers of t
        | `Blinded_root
        | `Too_large_values of t
        | `Empty ]
      [@@deriving irmin]
      (** The type for errors. *)

      val pp_error : error Fmt.t
      (** [pp_error] is the pretty-printer for errors. *)
    end

    val to_concrete : t -> Concrete.t
    (** [to_concrete t] is the concrete inode tree equivalent to [t]. *)

    val of_concrete : Concrete.t -> (t, Concrete.error) result
    (** [of_concrete c] is [Ok t] iff [c] and [t] are equivalent.

        The result is [Error e] when a subtree tree of [c] has an integrity
        error. *)

    module Portable : sig
      (* Extend to the portable signature *)
      include module type of Portable

      module Proof : sig
        val of_concrete : Concrete.t -> proof

        val to_concrete : proof -> Concrete.t
        (** This function produces unfindable keys. Only use in tests *)
      end
    end

    val of_snapshot :
      Snapshot.inode ->
      index:(hash -> key) ->
      (expected_depth:int -> key -> Raw.t option) ->
      t
  end

  val to_snapshot : Raw.t -> Snapshot.inode

  module Child_ordering : Child_ordering with type step := Val.step
end

module type Sigs = sig
  module type S = S
  module type Persistent = Persistent
  module type Internal = Internal
  module type Child_ordering = Child_ordering

  exception Max_depth of int

  module Make_internal
      (Conf : Conf.S)
      (H : Irmin.Hash.S) (Key : sig
        include Irmin.Key.S with type hash = H.t

        val unfindable_of_hash : hash -> t
      end)
      (Node : Irmin.Node.Generic_key.S
                with type hash = H.t
                 and type contents_key = Key.t
                 and type node_key = Key.t) :
    Internal
      with type hash = H.t
       and type key = Key.t
       and type Snapshot.metadata = Node.metadata
       and type Val.step = Node.step

  module Make
      (H : Irmin.Hash.S)
      (Key : Irmin.Key.S with type hash = H.t)
      (Node : Irmin.Node.Generic_key.S
                with type hash = H.t
                 and type contents_key = Key.t
                 and type node_key = Key.t)
      (Inter : Internal
                 with type hash = H.t
                  and type key = Key.t
                  and type Snapshot.metadata = Node.metadata
                  and type Val.step = Node.step)
      (Pack : Indexable.S
                with type key = Key.t
                 and type hash = H.t
                 and type value = Inter.Raw.t) :
    S
      with type 'a t = 'a Pack.t
       and type key = Key.t
       and type hash = H.t
       and type Val.metadata = Node.metadata
       and type Val.step = Node.step
       and type value = Inter.Val.t
end
