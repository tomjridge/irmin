include Pack_store_intf.Sigs
(** @inline *)

(*
sig
  module Indexing_strategy :
    sig
      type t = value_length:int -> Pack_value.Kind.t -> bool
      val always : t
      val minimal : t
      val default : t
    end
  module type S =
    sig
      type -'a t
      type key
      type value

   General question: a lot of these are direct and then lifted to lwt; why would layers work if the basic IO routines are not in Lwt? 

      val mem : [> Irmin__.Import.read ] t -> key -> bool Lwt.t
      val find : [> Irmin__.Import.read ] t -> key -> value option Lwt.t
      val close : 'a t -> unit Lwt.t
      type hash


      val index : [> Irmin__.Import.read ] t -> hash -> key option Lwt.t
index takes a hash and looks it up in the index, optionally returning a key

      val clear : 'a t -> unit Lwt.t
clear is like truncate? it clears the dictionary and index as well?


      val batch :
        Irmin__.Import.read t ->
        ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
what does this do? take a read only store, and perform a function that may require a writable store???


      module Key :
        sig
          type t = key
          val t : t Irmin__.Type.t
          type hash = hash
          val to_hash : t -> hash/2
        end

      val add : 'a t -> value -> key Lwt.t
add a particular value; presumably the value is hashable;


      val unsafe_add : 'a t -> hash -> value -> key Lwt.t
add a value whose hash is known; presumably no checks are made on whether the hash is consistent with the value?


      val index_direct : 'a t -> hash -> key option
??? a bit like index, but not in lwt?

      val unsafe_append :
        ensure_unique:bool -> overcommit:bool -> 'a t -> hash -> value -> key
ensure_unique: some way to avoid writing the same object more than once?
unclear what overcommit does -- presumably related to index?


      val unsafe_mem : 'a t -> key -> bool
      val unsafe_find : check_integrity:bool -> 'a t -> key -> value option
      type index
      val v :
        ?fresh:bool ->
        ?readonly:bool ->
        ?lru_size:int ->
        index:index ->
        indexing_strategy:Indexing_strategy.t ->
        string -> Import.read t Lwt.t
      val sync : 'a t -> unit
      val flush : ?index:bool -> ?index_merge:bool -> 'a t -> unit
      val offset : 'a t -> Import.int63
   Offset is the offset of the underlying IO instance; which is the "last flushed offset"?

      val clear_caches : 'a t -> unit
      val integrity_check :
        offset:Import.int63 ->
        length:int ->
        hash -> 'a t -> (unit, [ `Absent_value | `Wrong_hash ]) result
    end
  module type Maker =
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
                   offset_of_key:(hash Pack_key.t -> Import.int63 option) ->
                   hash -> t Irmin.Type.encode_bin
                 val decode_bin :
                   dict:(int -> string option) ->
                   key_of_offset:(Import.int63 -> hash Pack_key.t) ->
                   key_of_hash:(hash -> hash Pack_key.t) ->
                   t Irmin.Type.decode_bin
                 val decode_bin_length : string -> int -> int
               end)
          ->
          sig
            type -'a t
            type key = hash Pack_key.t
            type value = V.t
            val mem : [> Irmin__.Import.read ] t -> key -> bool Lwt.t
            val find :
              [> Irmin__.Import.read ] t -> key -> value option Lwt.t
            val close : 'a t -> unit Lwt.t
            type hash = hash
            val index :
              [> Irmin__.Import.read ] t -> hash/2 -> key option Lwt.t
            val clear : 'a t -> unit Lwt.t
            val batch :
              Irmin__.Import.read t ->
              ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
            module Key :
              sig
                type t = key
                val t : t Irmin__.Type.t
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
            val unsafe_find :
              check_integrity:bool -> 'a t -> key -> value option
            val v :
              ?fresh:bool ->
              ?readonly:bool ->
              ?lru_size:int ->
              index:index ->
              indexing_strategy:Indexing_strategy.t ->
              string -> Import.read t Lwt.t
            val sync : 'a t -> unit
            val flush : ?index:bool -> ?index_merge:bool -> 'a t -> unit
            val offset : 'a t -> Import.int63
            val clear_caches : 'a t -> unit
            val integrity_check :
              offset:Import.int63 ->
              length:int ->
              hash/2 ->
              'a t -> (unit, [ `Absent_value | `Wrong_hash ]) result
          end
    end
  val selected_version : Version.t
  module Maker :
    functor (Index : Pack_index.S)
      (Hash : sig
                type t = Index.key
                val hash : ((string -> unit) -> unit) -> t
                val short_hash : t -> int
                val hash_size : int
                val t : t Irmin__.Type.t
              end)
      ->
      sig
        type hash = Hash.t
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
                     offset_of_key:(hash Pack_key.t -> Import.int63 option) ->
                     hash -> t Irmin.Type.encode_bin
                   val decode_bin :
                     dict:(int -> string option) ->
                     key_of_offset:(Import.int63 -> hash Pack_key.t) ->
                     key_of_hash:(hash -> hash Pack_key.t) ->
                     t Irmin.Type.decode_bin
                   val decode_bin_length : string -> int -> int
                 end)
            ->
            sig
              type -'a t
              type key = hash Pack_key.t
              type value = V.t
              val mem : [> Irmin__.Import.read ] t -> key -> bool Lwt.t
              val find :
                [> Irmin__.Import.read ] t -> key -> value option Lwt.t
              val close : 'a t -> unit Lwt.t
              type hash = Hash.t
              val index :
                [> Irmin__.Import.read ] t -> hash -> key option Lwt.t
              val clear : 'a t -> unit Lwt.t
              val batch :
                Irmin__.Import.read t ->
                ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
              module Key :
                sig
                  type t = key
                  val t : t Irmin__.Type.t
                  type hash = Hash.t
                  val to_hash : t -> hash
                end
              val add : 'a t -> value -> key Lwt.t
              val unsafe_add : 'a t -> hash -> value -> key Lwt.t
              val index_direct : 'a t -> hash -> key option
              val unsafe_append :
                ensure_unique:bool ->
                overcommit:bool -> 'a t -> hash -> value -> key
              val unsafe_mem : 'a t -> key -> bool
              val unsafe_find :
                check_integrity:bool -> 'a t -> key -> value option
              val v :
                ?fresh:bool ->
                ?readonly:bool ->
                ?lru_size:int ->
                index:Index.t ->
                indexing_strategy:Indexing_strategy.t ->
                string -> Import.read t Lwt.t
              val sync : 'a t -> unit
              val flush : ?index:bool -> ?index_merge:bool -> 'a t -> unit
              val offset : 'a t -> Import.int63
              val clear_caches : 'a t -> unit
              val integrity_check :
                offset:Import.int63 ->
                length:int ->
                hash ->
                'a t -> (unit, [ `Absent_value | `Wrong_hash ]) result
            end
      end
end
*)
