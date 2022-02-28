open! Import

(** A [Pack_store.S] is a closeable, persistent implementation of {!Indexable.S}
    that uses an append-only file of variable-length data blocks.

    Certain values in the data file are indexed by hash via a {!Pack_index.S}
    implementation, but not all of them need be. *)
module type S = sig
  include Indexable.S

  type index
  type indexing_strategy

  val v :
    ?fresh:bool ->
    ?readonly:bool ->
    ?lru_size:int ->
    index:index ->
    indexing_strategy:indexing_strategy ->
    string ->
    read t Lwt.t

  val sync : 'a t -> unit
  (** Syncs a readonly instance with the files on disk. The same file instance
      is shared between several pack instances. *)

  val flush : ?index:bool -> ?index_merge:bool -> 'a t -> unit
  val offset : 'a t -> int63

  val clear_caches : 'a t -> unit
  (** [clear_cache t] clears all the in-memory caches of [t]. Persistent data
      are not removed. *)

  (** @inline *)
  include S.Checkable with type 'a t := 'a t and type hash := hash
end
(*
This is ultimately what Maker, Sigs below provide; value will be something like Pack_value; key will be [hash Pack_key.t]

sig
  type -'a t
  type key
  type value
  val mem : [> read ] t -> key -> bool Lwt.t
  val find : [> read ] t -> key -> value option Lwt.t
  val close : 'a t -> unit Lwt.t
  type hash
  val index : [> read ] t -> hash -> key option Lwt.t (from Indexable.S)
  val clear : 'a t -> unit Lwt.t
  val batch : read t -> ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
  module Key :
    sig
      type t = key
      val t : t Irmin.Type.ty
      type hash = hash
      val to_hash : t -> hash/2
    end
  FIXME why 'a t in following? Aren't these supposed to be permissioned somehow?
  val add : 'a t -> value -> key Lwt.t
  val unsafe_add : 'a t -> hash -> value -> key Lwt.t
  val index_direct : 'a t -> hash -> key option
  val unsafe_append :
    ensure_unique:bool -> overcommit:bool -> 'a t -> hash -> value -> key (also from Indexable.S)
  Hmmm; the ensure_unique here is a bit strange - presumably they are trying to avoid adding a value twice?

  val unsafe_mem : 'a t -> key -> bool
  val unsafe_find : check_integrity:bool -> 'a t -> key -> value option
  type index
  type indexing_strategy
  val v :
    ?fresh:bool ->
    ?readonly:bool ->
    ?lru_size:int ->
    index:index ->
    indexing_strategy:indexing_strategy -> string -> read t Lwt.t
  val sync : 'a t -> unit
  val flush : ?index:bool -> ?index_merge:bool -> 'a t -> unit
  val offset : 'a t -> int63
  val clear_caches : 'a t -> unit
  val integrity_check :
    offset:int63 ->
    length:int ->
    hash -> 'a t -> (unit, [ `Absent_value | `Wrong_hash ]) result
end
*)


module type Maker = sig
  type hash
  type index
  type indexing_strategy

  (** Save multiple kind of values in the same pack file. Values will be
      distinguished using [V.magic], so they have to all be different. *)

  module Make
      (V : Pack_value.Persistent
             with type hash := hash
              and type key := hash Pack_key.t) :
    S
      with type key = hash Pack_key.t
       and type hash = hash
       and type value = V.t
       and type index := index
       and type indexing_strategy := indexing_strategy
end

module type Sigs = sig
  module Indexing_strategy : sig
    type t = value_length:int -> Pack_value.Kind.t -> bool
    (** The type of configurations for [irmin-pack]'s indexing strategy, which
        dictates whether or not newly-appended pack entries should also be added
        to the index. Strategies are parameterised over:

        - the length of the binary encoding of the {i object} inside the pack
          entry (i.e. not accounting for the encoded hash and kind character);
        - the kind of the pack object having been added.

        Indexing more than the {!minimal} strategy only impacts performance and
        not correctness: more indexing results in a larger index and a smaller
        pack file. *)

    val always : t
    (** The strategy that indexes all objects. *)

    val minimal : t
    (** The strategy that indexes as few objects as possible while still
        maintaing store integrity. *)

    val default : t
    (** [default] is the indexing strategy used by [irmin-pack] instances that
        do not explicitly set an indexing strategy in {!Irmin_pack.config}.
        Currently set to {!always}. *)
  end

  module type S = S with type indexing_strategy := Indexing_strategy.t
  module type Maker = Maker with type indexing_strategy := Indexing_strategy.t
                                                             
  module type X = Maker (*
sig
  type hash
  type index
  module Make :
    functor
      (V : sig
             type t
             val t : t Irmin.Type.ty
             val hash : t -> hash
             val kind : t -> Pack_value.Kind.t
             val length_header :
               Pack_value.Kind.t -> Pack_value_intf.length_header
             val encode_bin :
               dict:(string -> int option) ->
               offset_of_key:(hash Pack_key.t -> int63 option) ->
               hash -> t Repr.encode_bin
             val decode_bin :
               dict:(int -> string option) ->
               key_of_offset:(int63 -> hash Pack_key.t) ->
               key_of_hash:(hash -> hash Pack_key.t) -> t Repr.decode_bin
             val decode_bin_length : string -> int -> int
           end)
      ->
      sig
        type -'a t
        type key = hash Pack_key.t
        type value = V.t
        val mem : [> Irmin.Perms.read ] t -> key -> bool Lwt.t
        val find : [> Irmin.Perms.read ] t -> key -> value option Lwt.t
        val close : 'a t -> unit Lwt.t
        type hash = hash
        val index : [> Irmin.Perms.read ] t -> hash/2 -> key option Lwt.t
        val clear : 'a t -> unit Lwt.t
        val batch :
          Irmin.Perms.read t ->
          ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
        module Key :
          sig
            type t = key
            val t : t Irmin.Type.ty
            type hash = hash
            val to_hash : t -> hash/2
          end
        val add : 'a t -> value -> key Lwt.t
        val unsafe_add : 'a t -> hash/2 -> value -> key Lwt.t
        val index_direct : 'a t -> hash/2 -> key option
        val unsafe_append :
          ensure_unique:bool ->
          overcommit:bool -> 'a t -> hash/2 -> value -> key
        val unsafe_mem : 'a t -> key -> bool
        val unsafe_find : check_integrity:bool -> 'a t -> key -> value option
        val v :
          ?fresh:bool ->
          ?readonly:bool ->
          ?lru_size:int ->
          index:index ->
          indexing_strategy:Indexing_strategy.t ->
          string -> Irmin.Perms.read t Lwt.t
        val sync : 'a t -> unit
        val flush : ?index:bool -> ?index_merge:bool -> 'a t -> unit
        val offset : 'a t -> int63
        val clear_caches : 'a t -> unit
        val integrity_check :
          offset:int63 ->
          length:int ->
          hash/2 -> 'a t -> (unit, [ `Absent_value | `Wrong_hash ]) result
      end
end
*)

  val selected_version : Version.t

  module Maker
      (Index : Pack_index.S)
      (Hash : Irmin.Hash.S with type t = Index.key) :
    Maker with type hash = Hash.t and type index := Index.t

end
