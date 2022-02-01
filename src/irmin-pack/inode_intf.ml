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

(* FIXME what is an inode? need ocamldoc here *)

(** An inode is used as part of a tree structure, to represent very large nodes. 

A node which contains many entries may become hard to manipulate in memory and store on
disk. An inode tree can be used to represent a single node. Only parts of the inode tree
need be kept in memory. Additions/deletions from the node may only affect single inodes in
the inode tree, so that most of the data for a node is unchanged between operations. *)


(** An interface describing how children of an inode are ordered. NOTE this is used in the
    {!Internal} interface. *)
module type Child_ordering = sig
  (** A step is something like a name in a directory; typically a string such as
      "filename.txt" *)
  type step

  (** A key is ... the cryptographic hash of the step? FIXME *)
  type key

  val key : step -> key
  (** We can compute the key of a step by hashing..? FIXME? *)

  val index : depth:int -> key -> int
  (** When attempting to locate a given key, in an inode tree, when at depth [depth]
      within the tree, we extract bits from the key; the bits are returned as an int *)
end

(* FIXME An inode value...? Seems to be something like a Node with generic key *)
(** A value is a "node value", see {!Irmin.Node.Generic_key.S} *)
module type Value = sig
  type key

  (** Include {!Irmin.Node.Generic_key.S} with [node_key] and [contents_key] set to
      [key] *)
  include
    Irmin.Node.Generic_key.S
      with type node_key = key
       and type contents_key = key

  (* FIXME what does pred do again??? what is the meaning of the result type? *)
  val pred :
    t ->
    (step option
    * [ `Node of node_key | `Inode of node_key | `Contents of contents_key ])
    list

  (** For [Portable] see {!Irmin.Node.Portable.S} *)
  module Portable :
    Irmin.Node.Portable.S
      with type node := t
       and type hash = hash
       and type step := step
       and type metadata := metadata

  (* FIXME here and elsewhere, are we talking about normal nodes, or inodes? *)
  val nb_children : t -> int
end


(** The signature of an inode store? *)
module type S = sig
  (** NOTE inodes are indexable *)
  include Irmin.Indexable.S (* really, the interface to a store of inodes *)
  module Hash : Irmin.Hash.S with type t = hash

  (* FIXME in the following a lot of types are not constrained; just not important? not used? *)
  module Val :
    Value
      with type t = value
       and type key = key
       and type hash = Hash.t
       and type Portable.hash := hash

  (* [decode_bin_length s off] returns the length of the entry encoded at position [off]
     in [s] FIXME why is this here, separate from decode/encode functions? *)
  val decode_bin_length : string -> int -> int
end

(** The signature for {b persistent} inodes; compared with {!S} this includes an index
    type, creation function (which needs an index), etc.  *)
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
  (* FIXME this opens a store? FIXME why [read t Lwt.t]? *)

  include S.Checkable with type 'a t := 'a t and type hash := hash

  val sync : 'a t -> unit
  val clear_caches : 'a t -> unit
  val integrity_check_inodes : [ `Read ] t -> key -> (unit, string) result Lwt.t
end

(** Unstable internal API agnostic about the underlying storage. Use it only to
    implement or test inodes. *)
module type Internal = sig
  type hash
  type key

  val pp_hash : hash Fmt.t

  (** A {b raw} inode, not much more than a pack value {!Pack_value.S}, but where it is
      possible to determine the depth of the corresponding inode within the inode tree? *)
  module Raw : sig
    include Pack_value.S with type hash = hash and type key = key

    val depth : t -> int option

    exception Invalid_depth of { expected : int; got : int; v : t }
  end

  module Val : sig
    include Value (* see intf above *) with type hash = hash and type key = key

    (* [of_raw f raw] - FIXME what does the [f] argument do? convert keys to Raws if
       possible? the keys are from children? and the expected depth argument? Presumably
       the [raw] value has a depth attached to it already, and expected_depth is then
       [d+1] for the children? *)
    val of_raw : (expected_depth:int -> key -> Raw.t option) -> Raw.t -> t

    val to_raw : t -> Raw.t
    (** [to_raw t] only converts the top-level inode to a raw inode? *)

    (* FIXME save to the pack.store ? FIXME why do we need these additional arguments? *)
    val save :
      add:(hash -> Raw.t -> key) ->
      index:(hash -> key option) ->
      mem:(key -> bool) ->
      t ->
      key
    (** [save ~add ~index ~mem t k] saves the value [t] and returns a key [k]; FIXME
        additional args? *)

    (** ff. indicate that from a [t] we can compute the hash; determine whether it is
        stable; and calculate the length FIXME of? *)
    val hash : t -> hash
    val stable : t -> bool
    val length : t -> int

    (* FIXME computer the index of a particular step? What does this mean? *)
    val index : depth:int -> step -> int

    val integrity_check : t -> bool
    (** Checks the integrity of an inode. *)

    (** [Concrete] trees *)
    module Concrete : sig
      (** {1 Concrete trees} *)

      (** The type for pointer kinds. FIXME why named kinded_key? FIXME a pointer is used for each entry? *)
      type kinded_key =
        | Contents of contents_key
        | Contents_x of metadata * contents_key
        | Node of node_key
      [@@deriving irmin]

      type entry = { name : step; key : kinded_key } [@@deriving irmin]
      (** The type of entries. *)
      (* FIXME the name here corresponds to the name of a file within a directory? the key is a pointer? *)

      type 'a pointer = { index : int; pointer : hash; tree : 'a }
      [@@deriving irmin]
      (** The type for internal pointers between concrete {!tree}s. FIXME what is this? When do you need internal pointers between concrete trees. What is a concrete tree? *)

      type 'a tree = { depth : int; length : int; pointers : 'a pointer list }
      [@@deriving irmin]
      (** The type for trees. A node in a concrete tree has a depth and a length (for
          pointers to children?) FIXME *)

      (** The type for concrete trees. *)
      type t = Tree of t tree | Values of entry list | Blinded
      [@@deriving irmin]
      (* NOTE that the leaf case is a [Values] of a list of entries FIXME what is [Blinded] *)


      (* Used for [`Invalid_length] constructor below *)
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
        | `Empty ]
      [@@deriving irmin]
      (** The type for errors. *)
      (* FIXME explain what these are and how they arise *)

      val pp_error : error Fmt.t
      (** [pp_error] is the pretty-printer for errors. *)
    end

    val to_concrete : t -> Concrete.t
    (** [to_concrete t] is the concrete inode tree equivalent to [t]. *)

    val of_concrete : Concrete.t -> (t, Concrete.error) result
    (** [of_concrete c] is [Ok t] iff [c] and [t] are equivalent.

        The result is [Error e] when a subtree tree of [c] has an integrity
        error. *)
    (* FIXME what is an example of an integrity error? one of the errors above? *)

    (** Extend the existing [Portable] module type with [Proof] submodule *)
    module Portable : sig
      include module type of Portable

      module Proof : sig
        val of_concrete : Concrete.t -> proof

        val to_concrete : proof -> Concrete.t
        (** This function produces unfindable keys. Only use in tests *)
      end
    end
  end

  module Child_ordering : Child_ordering with type step := Val.step
end

module type Sigs = sig
  module type S = S
  module type Persistent = Persistent
  module type Internal = Internal
  module type Child_ordering = Child_ordering

  exception Max_depth of int

  (** Functor args: [Conf] sets the max branching of the inode; [H] is for hashes; [Key]
      is like {!Irmin.Key.S} but with a way to coerce a hash to a key via
      [unfindable_of_hash] FIXME why needed? [Node] is the [Node] signature... FIXME why
      needed?  *)
  module Make_internal
      (Conf : Conf.S)
      (H : Irmin.Hash.S) 
      (Key : sig
        include Irmin.Key.S with type hash = H.t
                                               
        val unfindable_of_hash : hash -> t
        (* FIXME where is this used? *)
      end)
      (Node : Irmin.Node.Generic_key.S
                with type hash = H.t
                 and type contents_key = Key.t
                 and type node_key = Key.t) :
    Internal
      with type hash = H.t
       and type key = Key.t
       and type Val.metadata = Node.metadata
       and type Val.step = Node.step

  (** [Make] returns a module of type {!S}, i.e., of an inode store *)
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
                  and type Val.metadata = Node.metadata
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

  (** [Make_persistent] specializes [Key.t] to [H.t Pack_key.t], and uses [CA :
      Pack_store.Maker] to construct a [Persistent] interface; type [index] is fixed as a
      [Pack_index] *)
  module Make_persistent
      (H : Irmin.Hash.S)
      (Node : Irmin.Node.Generic_key.S
                with type hash = H.t
                 and type contents_key = H.t Pack_key.t
                 and type node_key = H.t Pack_key.t)
      (Inter : Internal
                 with type hash = H.t
                  and type key = H.t Pack_key.t
                  and type Val.metadata = Node.metadata
                  and type Val.step = Node.step)
      (CA : Pack_store.Maker
              with type hash = H.t
               and type index := Pack_index.Make(H).t) :
    Persistent
      with type key = H.t Pack_key.t
       and type hash = H.t
       and type Val.metadata = Node.metadata
       and type Val.step = Node.step
       and type index := Pack_index.Make(H).t
       and type value = Inter.Val.t
end
