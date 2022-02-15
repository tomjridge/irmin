(** {2 Concepts and terms} 

- low-level store (content-addressable; append-only; atomic-write)
- high-level store; example is a git repo;
- "There are two kinds of store in Irmin: the ones based on persistent named branches and the ones based temporary detached heads. These exist relative to a local, larger (and shared) store, and have some (shared) contents."
- Store vs Repo? maybe you have to go via Store.Repo.v to get a repo; then from a repo you can get a store back by Store.master repo; so stores are "checkedout branches in a repo"?
  - "repo t is the repository containing t." (repo contains stores)
- Path, a list of steps (strings)
- Backend 
- Hash
- Contents
- Node
- Node_portable
- Commit
- Commit_portable
- Branch
- Slice?
- Repo
- Remote
- KV: "These examples are using Irmin.KV, which is a specialization of Irmin.S with string list keys, string branches and no metadata."
- The block store. This is the type of store used for the commits, nodes and contents. The block store is persistent and content addressable
- "Concrete tree" vs tree; eg via Tree.to_concrete; concrete tree seems to have nice and simple recursive tree type; so maybe this is the thing we use to compare easily; presumably not possible if the tree is huge
- Store.of_branch: repo -> branch -> t Lwt.t with branch a string, indicates that a store is really a tree associated with a branch?
- pred? eg in Inode_intf.ml val pred... the previous neighbour in the tree?
*)

(** {2 Irmin.Contents} *)

module X3 = Irmin.Contents

module type X5 = Irmin.Contents.S
(* Essentially this is arbitrary, but we need a way to merge contents 
sig type t val t : t Repr__Type.t val merge : t option Irmin.Merge.t end
*)


(** {2 Irmin.Store_intf} *)

(* not exposed in the Irmin main module; Irmin.S is Store.S *)

module type X30 = Irmin.S
(*

type t in the following is Store.t; so can get empty store from a repo; main store from a repo; can get store from a repo and a branch (like main); can get store from a commit (presumably the tree associated with the commit); so a store is...?

  val empty : repo -> t Lwt.t
  val main : repo -> t Lwt.t
  val of_branch : repo -> branch -> t Lwt.t
  val of_commit : commit -> t Lwt.t
  val repo : t -> repo
  val tree : t -> tree Lwt.t
*)

module type X31 = Irmin.Maker (* = Store.Maker *)
module type X32 = Irmin.KV (* = Store.KV *)

(* from Irmin.Store_intf: 
module type Maker_generic_key = sig
  type endpoint

  include Key.Store_spec.S

  module Make (Schema : Schema.S) :
    S_generic_key
      with module Schema = Schema
       and type Backend.Remote.endpoint = endpoint
       and type contents_key = (Schema.Hash.t, Schema.Contents.t) contents_key
       and type node_key = Schema.Hash.t node_key
       and type commit_key = Schema.Hash.t commit_key
end

module type Maker =
  Maker_generic_key
    with type ('h, _) contents_key = 'h
     and type 'h node_key = 'h
     and type 'h commit_key = 'h

NOTE that Maker is a restriction of Maker_generic_key, where the keys are all hashes.
*)


(** {2 Irmin.Generic_key} *)

module X443 = Irmin.Generic_key
(* from irmin/store_intf.ml 

(** "Generic key" stores are Irmin stores in which the backend may not be keyed
    directly by the hashes of stored values. See {!Key} for more details. *)
module Generic_key : sig
  include module type of Store.Generic_key
  (** @inline *)

  module type Maker_args = sig
    module Contents_store : Indexable.Maker_concrete_key2
    module Node_store : Indexable.Maker_concrete_key1
    module Commit_store : Indexable.Maker_concrete_key1
    module Branch_store : Atomic_write.Maker
  end

  module Maker (X : Maker_args) :
    Maker
      with type ('h, 'v) contents_key = ('h, 'v) X.Contents_store.key
       and type 'h node_key = 'h X.Node_store.key
       and type 'h commit_key = 'h X.Commit_store.key
end

*)

(* The sig Maker here is: *)

module type X468 = Irmin.Maker

(*
(** [Maker] is the signature exposed by any backend providing {!S}
    implementations. [M] is the implementation of user-defined metadata, [C] is
    the one for user-defined contents, [B] is the implementation for branches
    and [H] is the implementation for object (blobs, trees, commits) hashes. It
    does not use any native synchronization primitives. *)
module type Maker = sig
  include Store.Maker
  (** @inline *)
end
*)

(* from Irmin.Store_intf: 
module type Maker_generic_key = sig
  type endpoint

  include Key.Store_spec.S

  module Make (Schema : Schema.S) :
    S_generic_key
      with module Schema = Schema
       and type Backend.Remote.endpoint = endpoint
       and type contents_key = (Schema.Hash.t, Schema.Contents.t) contents_key
       and type node_key = Schema.Hash.t node_key
       and type commit_key = Schema.Hash.t commit_key
end

module type Maker =
  Maker_generic_key
    with type ('h, _) contents_key = 'h
     and type 'h node_key = 'h
     and type 'h commit_key = 'h
*)



module type X441 = Irmin.Generic_key.KV_maker


(** {2 Irmin_pack.IO_intf.S} *)

(*
FIXME what effect does version have on the IO? version is stored in the header and checked when opening the file; other than that, it doesn't affect the IO code
module type S = sig
  type t
  type path := string

  val v : version:Version.t option -> fresh:bool -> readonly:bool -> path -> t
  val name : t -> string
  val append : t -> string -> unit
  val set : t -> off:int63 -> string -> unit
  val read : t -> off:int63 -> bytes -> int
  val read_buffer : t -> off:int63 -> buf:bytes -> len:int -> int
  val offset : t -> int63
  val force_offset : t -> int63
  val readonly : t -> bool
  val flush : t -> unit
  val close : t -> unit
  val exists : string -> bool
  val size : t -> int

  val truncate : t -> unit
  (** Sets the length of the underlying IO to be 0, without actually purging the
      associated data. *)

  (* {-2 Versioning} *)

  val version : t -> Version.t
  val set_version : t -> Version.t -> unit
end
*)


(** {2 Irmin_pack.S} *)

(* Irmin_pack.S not accessible outside irmin-pack *)

(*
FIXME why is Irmin.Generic_key.S the name for the store type? - I would expect this to be a sig for a generic key.

Checkable, Specifics are extensions to the Irmin standard Store intf, which is Irmin.Generic_key.S; then S is defined as 

module type S = sig
  include Irmin.Generic_key.S
  include Specifics with type repo := repo and type commit := commit

  val integrity_check_inodes :
    ?heads:commit list ->
    repo ->
    ([> `Msg of string ], [> `Msg of string ]) result Lwt.t

  val traverse_pack_file :
    [ `Reconstruct_index of [ `In_place | `Output of string ]
    | `Check_index
    | `Check_and_fix_index ] ->
    Irmin.config ->
    unit

  val stats :
    dump_blob_paths_to:string option -> commit:commit -> repo -> unit Lwt.t
end


*)


module type X4 = Irmin_pack.S

(** {2 Irmin_pack.IO_intf} *)

(*

Low-level interface to files; seems we can open this without bothering with pack etc.

module type S = sig
  type t
  type path := string

  val v : version:Version.t option -> fresh:bool -> readonly:bool -> path -> t
  val name : t -> string
  val append : t -> string -> unit
  val set : t -> off:int63 -> string -> unit
  val read : t -> off:int63 -> bytes -> int
  val read_buffer : t -> off:int63 -> buf:bytes -> len:int -> int
  val offset : t -> int63
  val force_offset : t -> int63
  val readonly : t -> bool
  val flush : t -> unit
  val close : t -> unit
  val exists : string -> bool
  val size : t -> int

  val truncate : t -> unit
  (** Sets the length of the underlying IO to be 0, without actually purging the
      associated data. *)

  (* {2 Versioning} *)

  val version : t -> Version.t
  val set_version : t -> Version.t -> unit
end

module type Sigs = sig
  module type S = S

  module Unix : S

  module Cache : sig
    type ('a, 'v) t = {
      v : 'a -> ?fresh:bool -> ?readonly:bool -> string -> 'v;
    }

    val memoize :
      v:('a -> fresh:bool -> readonly:bool -> string -> 'v) ->
      clear:('v -> unit) ->
      valid:('v -> bool) ->
      (root:string -> string) ->
      ('a, 'v) t
  end
end

*)


(** {2 Irmin_pack } *)

open Irmin_pack

(* Irmin_pack sig:
sig
  module Dict = Irmin_pack__.Pack_dict
  module Index = Irmin_pack__.Pack_index
  module Conf = Irmin_pack__.Conf
  module Inode = Irmin_pack__.Inode
  module Pack_key = Irmin_pack__.Pack_key
  module Pack_value = Irmin_pack__.Pack_value
  module Pack_store = Irmin_pack__.Pack_store
  val config :
    ?fresh:bool ->
    ?readonly:bool ->
    ?lru_size:int ->
    ?index_log_size:int ->
    ?merge_throttle:Conf.merge_throttle ->
    ?freeze_throttle:Conf.freeze_throttle -> string -> Irmin.config
  exception RO_not_allowed
  module KV :
    Conf.S ->
      sig
        [huge signature here]
      end
  module type S = Irmin_pack.S
  module type Specifics = Irmin_pack.Specifics
  module type Maker = Irmin_pack.Maker
  module type Maker_persistent = Irmin_pack.Maker_persistent
  module Maker : Maker_persistent
  module Stats = Irmin_pack__.Stats
  module Layout = Irmin_pack__.Layout
  module Checks = Irmin_pack__.Checks
  module Indexable = Irmin_pack__.Indexable
  module Atomic_write = Irmin_pack__.Atomic_write
  module IO = Irmin_pack__.IO
  module Utils = Irmin_pack__.Utils
end

*)



(** {2 Irmin_pack.Conf} *)

module X46 = Irmin_pack.Conf
(*
Seems quite short; contents_length_header is a bit weird
FIXME what are S.entries, S.stable_hash?

type length_header = [ `Varint ] option

module type S = sig
  val entries : int
  val stable_hash : int

  val contents_length_header : length_header
  (** Describes the length header of the user's contents values when
      binary-encoded. Supported modes are:

      - [Some `Varint]: the length header is a LEB128-encoded integer at the
        very beginning of the encoded value.

      - [None]: there is no length header, and values have unknown size. *)
end

val spec : Irmin.Backend.Conf.Spec.t

type merge_throttle = [ `Block_writes | `Overcommit_memory ] [@@deriving irmin]
type freeze_throttle = [ merge_throttle | `Cancel_existing ] [@@deriving irmin]

module Key : sig
  val fresh : bool Irmin.Backend.Conf.key
  val lru_size : int Irmin.Backend.Conf.key
  val index_log_size : int Irmin.Backend.Conf.key
  val readonly : bool Irmin.Backend.Conf.key
  val root : string Irmin.Backend.Conf.key
  val merge_throttle : merge_throttle Irmin.Backend.Conf.key
  val freeze_throttle : freeze_throttle Irmin.Backend.Conf.key
end


*)


(** {2 Irmin_pack.Pack_key} *)

module _ = Irmin_pack.Pack_key

(*
The type of the hash is an explicit type param

FIXME what is Store_spec? 

Note the sig Store_spec and the module are the same (using module rec)

sig
  type 'hash t = 'hash
  module type S = Pack_key.S
  module Make = Irmin_pack.Pack_key.Make
  module type Store_spec =
    sig
      type ('h, _) contents_key = 'h
      type 'h node_key = 'h
      type 'h commit_key = 'h
    end
  module Store_spec = Pack_key.Store_spec
end
*)

module type X110 = Irmin_pack.Pack_key.S
(*
FIXME What is this a signature for? We already have type 'hash t...

sig
  type hash
  type t = hash
  val t : t Irmin__.Type.t
  val to_hash : t -> t
  val null : t
end
*)

module _ = Irmin_pack.Pack_key.Make

(*
functor (Hash : Irmin.Hash.S) ->
  sig
    type hash = Hash.t
    type t = hash
    val t : t Irmin__.Type.t
    val to_hash : t -> t
    val null : t
  end
*)

module _ = Pack_key.Store_spec


(** {2 Irmin_pack.Pack_value} *)

module _ = Irmin_pack.Pack_value.Kind

(*
sig
  type t =
    Irmin_pack.Pack_value.Kind.t =
      Commit_v0
    | Commit_v1
    | Contents
    | Inode_v0_unstable
    | Inode_v0_stable
    | Inode_v1_root
    | Inode_v1_nonroot
  val t : t Irmin.Type.t
  val all : t list
  val to_enum : t -> int
  val to_magic : t -> char
  val of_magic_exn : char -> t
  val version : t -> Irmin_pack__.Version.t
  val pp : t Fmt.t
end
*)

module _ = Irmin_pack.Pack_value

(*

sig
  module Kind = Irmin_pack.Pack_value.Kind
  module type S =
    sig
      type t
      val t : t Irmin.Type.ty
      type hash
      type key
      val hash : t -> hash
      val kind : t -> Kind.t
      val length_header :
        [ `Never | `Sometimes of Kind.t -> [ `Varint ] option ]
      val encode_bin :
        dict:(string -> int option) ->
        offset_of_key:(key -> Irmin_pack__Import.int63 option) ->
        hash -> t Irmin.Type.encode_bin
      val decode_bin :
        dict:(int -> string option) ->
        key_of_offset:(Irmin_pack__Import.int63 -> key) ->
        key_of_hash:(hash -> key) -> t Irmin.Type.decode_bin
      val decode_bin_length : string -> int -> int
    end
  module type Persistent =
    sig
      type hash
      type t
      val t : t Irmin.Type.ty
      type key = hash Pack_key.t
      val hash : t -> hash
      val kind : t -> Kind.t
      val length_header :
        [ `Never | `Sometimes of Kind.t -> [ `Varint ] option ]
      val encode_bin :
        dict:(string -> int option) ->
        offset_of_key:(key -> Irmin_pack__Import.int63 option) ->
        hash -> t Irmin.Type.encode_bin

FIXME What are the offset_of_key parameters? Why does encode_bin need to take extra parameters?

      val decode_bin :
        dict:(int -> string option) ->
        key_of_offset:(Irmin_pack__Import.int63 -> key) ->
        key_of_hash:(hash -> key) -> t Irmin.Type.decode_bin
      val decode_bin_length : string -> int -> int
    end
  module Of_contents = Irmin_pack.Pack_value.Of_contents
  module Of_commit = Irmin_pack.Pack_value.Of_commit
end

Persistent defined as: 
module type Persistent = sig
  type hash

  include S with type hash := hash and type key = hash Pack_key.t
end


*)


(** {2 Irmin_pack.Index} *)

module _ = Irmin_pack.Index
(*
sig
  module type S = Irmin_pack__.Pack_index_intf.S
  module Make = Irmin_pack__Pack_index.Make
end
*)

module type X235 = Irmin_pack.Index.S
(*

sig
  type t
  type key
  type value = Irmin_pack__Import.int63 * int * Pack_value.Kind.t
  type cache
  val empty_cache : unit -> cache
  val clear : t -> unit
  val mem : t -> key -> bool
  val replace : ?overcommit:bool -> t -> key -> value -> unit
  val filter : t -> (key * value -> bool) -> unit
  val iter : (key -> value -> unit) -> t -> unit
  val flush : ?no_callback:unit -> ?with_fsync:bool -> t -> unit
  val sync : t -> unit
  val is_merging : t -> bool
  val try_merge : t -> unit
  module Checks :
    sig ...
    end
  val v :
    ?flush_callback:(unit -> unit) ->
    ?fresh:bool ->
    ?readonly:bool ->
    ?throttle:[ `Block_writes | `Overcommit_memory ] ->
    ?lru_size:int -> log_size:int -> string -> t
  val find : t -> key -> value option
  val add : ?overcommit:bool -> t -> key -> value -> unit
  val close : t -> unit
  val merge : t -> unit
  module Stats = Index.Stats
end
*)


(** {2 Irmin_pack.Indexable} *)

module _ = Irmin_pack.Indexable
(*
sig
  module type S = Indexable.S
  module Closeable = Irmin_pack.Indexable.Closeable
end
*)

module type X281 = Irmin_pack.Indexable.S
(*
Defined as: 
module type S = sig
  include Irmin.Indexable.S

  val add : 'a t -> value -> key Lwt.t
  (** Overwrite [add] to work with a read-only database handler. *)

  val unsafe_add : 'a t -> hash -> value -> key Lwt.t
  (** Overwrite [unsafe_add] to work with a read-only database handler. *)

  val index_direct : _ t -> hash -> key option

  val unsafe_append :
    ensure_unique:bool -> overcommit:bool -> 'a t -> hash -> value -> key

  val unsafe_mem : 'a t -> key -> bool
  val unsafe_find : check_integrity:bool -> 'a t -> key -> value option
end

Result sig:
sig
  type -'a t
  type key
  type value
  val mem : [> Irmin__Import.read ] t -> key -> bool Lwt.t
  val find : [> Irmin__Import.read ] t -> key -> value option Lwt.t
  val close : 'a t -> unit Lwt.t
  type hash
  val index : [> Irmin__Import.read ] t -> hash -> key option Lwt.t
  val clear : 'a t -> unit Lwt.t
  val batch :
    Irmin__Import.read t -> ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
  module Key :
    sig
      type t = key
      val t : t Irmin__Type.t
      type hash = hash
      val to_hash : t -> hash/2
    end
  val add : 'a t -> value -> key Lwt.t
  val unsafe_add : 'a t -> hash -> value -> key Lwt.t
  val index_direct : 'a t -> hash -> key option
  val unsafe_append :
    ensure_unique:bool -> overcommit:bool -> 'a t -> hash -> value -> key
  val unsafe_mem : 'a t -> key -> bool
  val unsafe_find : check_integrity:bool -> 'a t -> key -> value option
end
*)


(** {2 Irmin_pack.Pack_store} *)

module _ = Irmin_pack.Pack_store
(*
sig
  module type S = Pack_store.S
  module type Maker = Pack_store.Maker
  val selected_version : Irmin_pack__Version.t 
  module Maker = Maker
end
*)

module type X345 = Irmin_pack.Pack_store.S
(* This includes Indexable.S, then extends with type index onwards
sig
  type -'a t
  type key
  type value
  val mem : [> Irmin__.Import.read ] t -> key -> bool Lwt.t
  val find : [> Irmin__.Import.read ] t -> key -> value option Lwt.t
  val close : 'a t -> unit Lwt.t
  type hash
  val index : [> Irmin__.Import.read ] t -> hash -> key option Lwt.t
  val clear : 'a t -> unit Lwt.t
  val batch :
    Irmin__.Import.read t -> ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
  module Key :
    sig
      type t = key
      val t : t Irmin__.Type.t
      type hash = hash
      val to_hash : t -> hash/2
    end
  val add : 'a t -> value -> key Lwt.t
  val unsafe_add : 'a t -> hash -> value -> key Lwt.t
  val index_direct : 'a t -> hash -> key option
  val unsafe_append :
    ensure_unique:bool -> overcommit:bool -> 'a t -> hash -> value -> key
  val unsafe_mem : 'a t -> key -> bool
  val unsafe_find : check_integrity:bool -> 'a t -> key -> value option
--- Indexable.S above here
  type index
  val v :
    ?fresh:bool ->
    ?readonly:bool ->
    ?lru_size:int -> index:index -> string -> Irmin_pack__Import.read t Lwt.t
  val sync : 'a t -> unit
  val flush : ?index:bool -> ?index_merge:bool -> 'a t -> unit
  val offset : 'a t -> Irmin_pack__Import.int63
  val clear_caches : 'a t -> unit
  val integrity_check :
    offset:Irmin_pack__Import.int63 ->
    length:int ->
    hash -> 'a t -> (unit, [ `Absent_value | `Wrong_hash ]) result
  val debug_block : 'a t -> IO.Unix.t
end
*)


module type X392 = Irmin_pack.Pack_store.Maker

(*
module type Maker = sig
  type hash
  type index

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
end
*)



(** {2 Irmin_pack.Traverse_pack_file} *)

module X621 = Irmin_pack__.Traverse_pack_file
module X622 = Irmin_pack__.Traverse_pack_file.Make
(* 
functor (Args : X621.Args) ->
  sig
    val run :
      [ `Check_and_fix_index
      | `Check_index
      | `Reconstruct_index of [ `In_place | `Output of string ] ] ->
      Irmin.config -> unit
  end
*)


(** {2 Irmin_pack.Ext module - very useful to examine with merlin types} *)

(* NOTE ext is not accessible from outside irmin_pack; intf ext.mli is:

module Maker (_ : Conf.S) : S.Maker_persistent

Then, what is the implementation type of the result?

ext.ml starts as: 

module Maker (Config : Conf.S) = struct
  type endpoint = unit

  include Pack_key.Store_spec

  module Make (Schema : Irmin.Schema.Extended) = struct
    open struct
      module P = Schema.Path
      module M = Schema.Metadata
      module C = Schema.Contents
      module B = Schema.Branch
    end

    module H = Schema.Hash
    module Index = Pack_index.Make (H)
    module Pack = Pack_store.Maker (Index) (H)


And here we can see the definition of the Pack module

Then later: 

    module X = struct
      module Hash = H

      type 'a value = { hash : H.t; kind : Pack_value.Kind.t; v : 'a }
      [@@deriving irmin]

      module Contents = struct
        module Pack_value = Pack_value.Of_contents (Config) (H) (XKey) (C)
        module CA = Pack.Make (Pack_value)
        include Irmin.Contents.Store_indexable (CA) (H) (C)
      end

And CA is the backend store that has the debug_block function

sig for CA:

sig
  type 'a t = 'a Pack_store.Maker(Index)(Hash).Make(Pack_value).t
  type key = Pack_value.key
  type value = Pack_value.t
  val mem : [> read ] t -> key -> bool Lwt.t
  val find : [> read ] t -> key -> value option Lwt.t
  val close : 'a t -> endpoint Lwt.t
  type hash = Pack_value.key
  val index : [> read ] t -> hash -> key option Lwt.t
  val clear : 'a t -> endpoint Lwt.t
  val batch : read t -> ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
  module Key :
    sig
      type t = key
      val t : t Repr.ty
      type hash = Pack_value.key
      val to_hash : t -> hash
    end
  val add : 'a t -> value -> key Lwt.t
  val unsafe_add : 'a t -> hash -> value -> key Lwt.t
  val index_direct : 'a t -> hash -> key option
  val unsafe_append :
    ensure_unique:bool -> overcommit:bool -> 'a t -> hash -> value -> key
  val unsafe_mem : 'a t -> key -> bool
  val unsafe_find : check_integrity:bool -> 'a t -> key -> value option
  val v :
    ?fresh:bool ->
    ?readonly:bool ->
    ?lru_size:int -> index:Index.t -> string -> read t Lwt.t
  val sync : 'a t -> endpoint
  val flush : ?index:bool -> ?index_merge:bool -> 'a t -> endpoint
  val offset : 'a t -> int63
  val clear_caches : 'a t -> endpoint
  val integrity_check :
    offset:int63 ->
    length:int ->
    hash -> 'a t -> (endpoint, [ `Absent_value | `Wrong_hash ]) result
  val debug_block : 'a t -> Irmin_pack__.IO.Unix.t
end

And 'a t = 'a Pack_store.Maker(Index)(Hash).Make(Pack_value).t

Pack_store is where the type IO.t comes in: 

  type 'a t = {
    mutable block : IO.t;
    index : Index.t;
    dict : Dict.t;
    mutable open_instances : int;
  }

And the IO.t is the thing with the version

So, actually the IO.t could be for the index file, or the root file

*)




(** {2 Irmin_pack, Irmin_pack_intf} *)

(* module X428 = Irmin_pack_intf (\* this is inaccessible from outside the Irmin_pack lib *\) *)

module X430 = Irmin_pack.KV

(* defined as
  module KV (_ : Conf.S) :
    Irmin.Generic_key.KV_maker
      with type metadata = unit
       and type ('h, 'v) contents_key = 'h Pack_key.t
       and type 'h node_key = 'h Pack_key.t
       and type 'h commit_key = 'h Pack_key.t

And the result, the KV_maker, is again a container for a Make functor
*)

(* for Generic_key, see prev section *)

(** {2 Assembling an Irmin_pack.KV} *)

(* 


Conf --(some functors)-> Store

dir -> config -> repo (via Irmin_pack.config, Store.Repo.v config)

main : Store.t = (from repo via Store.main)

Store.set_tree_exn .. [] (Store.Tree.empty()) // set the contents of the path [] to the empty tree 

*)

module Store_ = struct
  (* Craig slack 2021-12-13@11:02

module Store = Irmin_pack.KV (Common.Conf)

let test () =
  let config = Irmin_pack.config "./data/version_1" in
  let* store = Store.Repo.v config >>= Store.main in
  Store.set_tree_exn store [] (Store.Tree.empty ())
  *)
  
  (* taken from common.ml *)
  module Conf = Irmin_tezos.Conf 

  (* Store1 seems to be not much more than a holder for the Make functor *)
  module Store1 = Irmin_pack.KV(Conf) 

  module Store2 = Store1.Make(Irmin.Contents.String)
  module Store = Store2

  (* Store2 has a huge signature *)


  type mode = [`RW | `RO]
  open Lwt.Infix

  module With_(S:sig val mode:mode val dir:string end) = struct
    open S
    let config : Irmin.config = Irmin_pack.config ~readonly:(mode=`RO) dir
   
    let repo : Store.repo Lwt.t = Store.Repo.v config

    (* get main branch *)
    let main : Store.t Lwt.t = repo >>= fun store -> Store.main store

    let add_tree () : unit Lwt.t = 
      main >>= fun main -> 
      let info () = Store.Info.v (Int64.of_int 0) in
      Store.set_tree_exn ~info main [] (Store.Tree.empty ())

    let force_version_bump () = add_tree ()

    (* how to get the version from a repo? *)

    let close () : unit Lwt.t = repo >>= fun repo -> Store.Repo.close repo
  end    
 
end

(** {2 Huge Store_.Store2 type (result of Irmin_pack.KV.Make(...)) } *)

module type X592 = (* module type of Store_.Store = *) sig
  module Schema = Store_.Store2.Schema
  type repo = Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).repo
  type t = Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).t
  type step = string
  val step_t : step Repr__Type.t
  type path = Schema.Path.t
  val path_t : path Repr__Type.t
  type metadata = unit
  val metadata_t : metadata Repr__Type.t
  type contents = step
  val contents_t : step Repr__Type.t
  type node = Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).node
  val node_t : node Repr__Type.t
  type tree = Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).tree
  val tree_t : tree Repr__Type.t
  type hash = Schema.Hash.t
  val hash_t : hash Repr__Type.t
  type commit = Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).commit
  val commit_t : repo -> commit Repr__Type.t
  type branch = contents
  val branch_t : step Repr__Type.t
  type slice = Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).slice
  val slice_t : slice Repr__Type.t
  type info = Schema.Info.t
  val info_t : info Repr__Type.t
  type lca_error = [ `Max_depth_reached | `Too_many_lcas ]
  val lca_error_t : lca_error Repr__Type.t
  type ff_error =
      [ `Max_depth_reached | `No_change | `Rejected | `Too_many_lcas ]
  val ff_error_t : ff_error Repr__Type.t
  module Info = Store_.Store2.Info
  type contents_key = Store_.Store1.hash
  val contents_key_t : contents_key Repr__Type.t
  type node_key = Store_.Store1.hash
  val node_key_t : node_key Repr__Type.t
  type commit_key = Store_.Store1.hash
  val commit_key_t : commit_key Repr__Type.t
  module Repo = Store_.Store2.Repo
  val empty : repo -> t Lwt.t
  val main : repo -> t Lwt.t
  val of_branch : repo -> branch -> t Lwt.t
  val of_commit : commit -> t Lwt.t
  val repo : t -> repo
  val tree : t -> tree Lwt.t
  module Status = Store_.Store2.Status
  val status : t -> Status.t
  module Head = Store_.Store2.Head
  module Hash = Store_.Store2.Hash
  module Commit = Store_.Store2.Commit
  module Contents = Store_.Store2.Contents
  module Tree = Store_.Store2.Tree
  val kind : t -> path -> [ `Contents | `Node ] option Lwt.t
  val list : t -> path -> (step * tree) list Lwt.t
  val mem : t -> path -> bool Lwt.t
  val mem_tree : t -> path -> bool Lwt.t
  val find_all : t -> path -> (step * metadata) option Lwt.t
  val find : t -> path -> step option Lwt.t
  val get_all : t -> path -> (step * metadata) Lwt.t
  val get : t -> path -> step Lwt.t
  val find_tree : t -> path -> tree option Lwt.t
  val get_tree : t -> path -> tree Lwt.t
  val key :
    t ->
    path -> [ `Contents of contents_key | `Node of node_key ] option Lwt.t
  val hash : t -> path -> hash option Lwt.t
  type write_error =
      [ `Conflict of branch
      | `Test_was of tree option
      | `Too_many_retries of int ]
  val write_error_t : write_error Repr__Type.t
  val set :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t -> path -> branch -> (metadata, write_error) result Lwt.t
  val set_exn :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f -> t -> path -> branch -> metadata Lwt.t
  val set_tree :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f -> t -> path -> tree -> (metadata, write_error) result Lwt.t
  val set_tree_exn :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f -> t -> path -> tree -> metadata Lwt.t
  val remove :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f -> t -> path -> (metadata, write_error) result Lwt.t
  val remove_exn :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list -> info:Info.f -> t -> path -> metadata Lwt.t
  val test_and_set :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    test:branch option ->
    set:branch option -> (metadata, write_error) result Lwt.t
  val test_and_set_exn :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t -> path -> test:branch option -> set:branch option -> metadata Lwt.t
  val test_and_set_tree :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t ->
    path ->
    test:tree option ->
    set:tree option -> (metadata, write_error) result Lwt.t
  val test_and_set_tree_exn :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    t -> path -> test:tree option -> set:tree option -> metadata Lwt.t
  val merge :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    old:branch option ->
    t -> path -> branch option -> (metadata, write_error) result Lwt.t
  val merge_exn :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    old:branch option -> t -> path -> branch option -> metadata Lwt.t
  val merge_tree :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    old:tree option ->
    t -> path -> tree option -> (metadata, write_error) result Lwt.t
  val merge_tree_exn :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    info:Info.f ->
    old:tree option -> t -> path -> tree option -> metadata Lwt.t
  val with_tree :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    ?strategy:[ `Merge | `Set | `Test_and_set ] ->
    info:Info.f ->
    t ->
    path ->
    (tree option -> tree option Lwt.t) ->
    (metadata, write_error) result Lwt.t
  val with_tree_exn :
    ?retries:int ->
    ?allow_empty:bool ->
    ?parents:commit list ->
    ?strategy:[ `Merge | `Set | `Test_and_set ] ->
    info:Info.f ->
    t -> path -> (tree option -> tree option Lwt.t) -> metadata Lwt.t
  val clone : src:t -> dst:branch -> t Lwt.t
  type watch = Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).watch
  val watch :
    t -> ?init:commit -> (commit Irmin.diff -> metadata Lwt.t) -> watch Lwt.t
  val watch_key :
    t ->
    path ->
    ?init:commit ->
    ((commit * tree) Irmin.diff -> metadata Lwt.t) -> watch Lwt.t
  val unwatch : watch -> metadata Lwt.t
  type 'a merge =
      info:Info.f ->
      ?max_depth:int ->
      ?n:int -> 'a -> (metadata, Irmin.Merge.conflict) result Lwt.t
  val merge_into : into:t -> t merge
  val merge_with_branch : t -> branch merge
  val merge_with_commit : t -> commit merge
  val lcas :
    ?max_depth:int ->
    ?n:int -> t -> t -> (commit list, lca_error) result Lwt.t
  val lcas_with_branch :
    t ->
    ?max_depth:int ->
    ?n:int -> branch -> (commit list, lca_error) result Lwt.t
  val lcas_with_commit :
    t ->
    ?max_depth:int ->
    ?n:int -> commit -> (commit list, lca_error) result Lwt.t
  module History = Store_.Store2.History
  val history :
    ?depth:int ->
    ?min:commit list -> ?max:commit list -> t -> History.t Lwt.t
  val last_modified : ?depth:int -> ?n:int -> t -> path -> commit list Lwt.t
  module Branch = Store_.Store2.Branch
  module Path = Store_.Store2.Path
  module Metadata = Store_.Store2.Metadata
  module Backend = Store_.Store2.Backend
  type Irmin.remote += E of Backend.Remote.endpoint
  val of_backend_node : repo -> Backend.Node.value -> node
  val to_backend_node : node -> Backend.Node.value Lwt.t
  val to_backend_portable_node : node -> Backend.Node_portable.t Lwt.t
  val to_backend_commit : commit -> Backend.Commit.value
  val of_backend_commit :
    repo -> Store_.Store2.commit_key -> Backend.Commit.value -> commit
  val save_contents :
    [> Irmin.Perms.write ] Backend.Contents.t -> step -> contents_key Lwt.t
  val save_tree :
    ?clear:bool ->
    repo ->
    [> Irmin.Perms.write ] Backend.Contents.t ->
    [> Irmin.Perms.read_write ] Backend.Node.t ->
    tree -> [ `Contents of contents_key | `Node of node_key ] Lwt.t
  val master : repo -> t Lwt.t
end

module type X821 = (*module type of Store_.Store2.Backend =*) sig
  module Schema :
    sig
      module Hash :
        sig
          type t = Store_.Store2.Schema.Hash.t
          val hash : ((string -> unit) -> unit) -> t
          val short_hash : t -> int
          val hash_size : int
          val t : t Repr__Type.t
        end
      module Branch :
        sig
          type t = string
          val t : t Repr__Type.t
          val main : t
          val is_valid : t -> bool
        end
      module Info :
        sig
          type author = string
          val author_t : author Repr__Type.t
          type message = author
          val message_t : author Repr__Type.t
          type t = Store_.Store2.Schema.Info.t
          val t : t Repr__Type.t
          val v : ?author:message -> ?message:message -> int64 -> t
          val date : t -> int64
          val author : t -> message
          val message : t -> message
          val empty : t
          type f = unit -> t
          val none : f
        end
      module Metadata :
        sig
          type t = unit
          val t : t Repr__Type.t
          val default : t
          val merge : t Irmin.Merge.t
        end
      module Path :
        sig
          type t = Store_.Store2.path
          type step = string
          val empty : t
          val v : step list -> t
          val is_empty : t -> bool
          val cons : step -> t -> t
          val rcons : t -> step -> t
          val decons : t -> (step * t) option
          val rdecons : t -> (t * step) option
          val map : t -> (step -> 'a) -> 'a list
          val t : t Repr__Type.t
          val step_t : step Repr__Type.t
        end
      module Contents :
        sig
          type t = string
          val t : t Repr__Type.t
          val merge : t option Irmin.Merge.t
        end
    end
  module Hash :
    sig
      type t = Store_.Store2.hash
      val hash : ((string -> unit) -> unit) -> t
      val short_hash : t -> int
      val hash_size : int
      val t : t Repr__Type.t
    end
  module Contents :
    sig
      type 'a t =
          'a
          Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Contents.t
      type key = Store_.Store2.contents_key
      type value = string
      val mem : [> Irmin.Perms.read ] t -> key -> bool Lwt.t
      val find : [> Irmin.Perms.read ] t -> key -> value option Lwt.t
      val close : 'a t -> unit Lwt.t
      type hash = Hash.t
      val add : [> Irmin.Perms.write ] t -> value -> key Lwt.t
      val unsafe_add : [> Irmin.Perms.write ] t -> hash -> value -> key Lwt.t
      val index : [> Irmin.Perms.read ] t -> hash -> key option Lwt.t
      val clear : 'a t -> unit Lwt.t
      val batch :
        Irmin.Perms.read t -> ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
      module Key :
        sig
          type t = key
          val t : t Repr__Type.t
          type nonrec hash = hash
          val to_hash : t -> hash
        end
      val merge : [> Irmin.Perms.read_write ] t -> key option Irmin.Merge.t
      module Val :
        sig
          type t = value
          val t : t Repr__Type.t
          val merge : t option Irmin.Merge.t
        end
      module Hash :
        sig
          type t = hash
          type value = string
          val hash : value -> t
          val short_hash : t -> int
          val hash_size : int
          val t : t Repr__Type.t
        end
    end
  module Node :
    sig
      type 'a t =
          'a
          Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Node.t
      type key = Store_.Store2.node_key
      type value =
          Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Node.value
      val mem : [> Irmin.Perms.read ] t -> key -> bool Lwt.t
      val find : [> Irmin.Perms.read ] t -> key -> value option Lwt.t
      val close : 'a t -> unit Lwt.t
      type hash = Hash.t
      val add : [> Irmin.Perms.write ] t -> value -> key Lwt.t
      val unsafe_add : [> Irmin.Perms.write ] t -> hash -> value -> key Lwt.t
      val index : [> Irmin.Perms.read ] t -> hash -> key option Lwt.t
      val clear : 'a t -> unit Lwt.t
      val batch :
        Irmin.Perms.read t -> ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
      module Key :
        sig
          type t = key
          val t : t Repr__Type.t
          type nonrec hash = hash
          val to_hash : t -> hash
        end
      module Path :
        sig
          type t = Schema.Path.t
          type step = string
          val empty : t
          val v : step list -> t
          val is_empty : t -> bool
          val cons : step -> t -> t
          val rcons : t -> step -> t
          val decons : t -> (step * t) option
          val rdecons : t -> (t * step) option
          val map : t -> (step -> 'a) -> 'a list
          val t : t Repr__Type.t
          val step_t : step Repr__Type.t
        end
      val merge : [> Irmin.Perms.read_write ] t -> key option Irmin.Merge.t
      module Metadata :
        sig
          type t = unit
          val t : t Repr__Type.t
          val default : t
          val merge : t Irmin.Merge.t
        end
      module Val :
        sig
          type t = value
          val t : t Repr__Type.t
          type metadata = unit
          val metadata_t : metadata Repr__Type.t
          type contents_key = Contents.key
          val contents_key_t : contents_key Repr__Type.t
          type node_key = key
          val node_key_t : node_key Repr__Type.t
          type step = string
          val step_t : step Repr__Type.t
          type value =
              [ `Contents of contents_key * metadata | `Node of node_key ]
          val value_t : value Repr__Type.t
          type nonrec hash = hash
          val hash_t : hash Repr__Type.t
          val of_list : (step * value) list -> t
          val list :
            ?offset:int ->
            ?length:int -> ?cache:bool -> t -> (step * value) list
          val of_seq : (step * value) Irmin__Import.Seq.t -> t
          val seq :
            ?offset:int ->
            ?length:int ->
            ?cache:bool -> t -> (step * value) Irmin__Import.Seq.t
          val empty : metadata -> t
          val is_empty : t -> bool
          val length : t -> int
          val clear : t -> metadata
          val find : ?cache:bool -> t -> step -> value option
          val add : t -> step -> value -> t
          val remove : t -> step -> t
          module Metadata :
            sig
              type t = metadata
              val t : t Repr__Type.t
              val default : t
              val merge : t Irmin.Merge.t
            end
          val merge :
            contents:contents_key option Irmin.Merge.t ->
            node:node_key option Irmin.Merge.t -> t Irmin.Merge.t
        end
      module Hash :
        sig
          type t = hash
          type nonrec value = value
          val hash : value -> t
          val short_hash : t -> int
          val hash_size : int
          val t : t Repr__Type.t
        end
      module Contents :
        sig
          type 'a t =
              'a
              Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Node.Contents.t
          type key = Val.contents_key
          type value =
              Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Node.Contents.value
          val mem : [> Irmin.Perms.read ] t -> key -> bool Lwt.t
          val find : [> Irmin.Perms.read ] t -> key -> value option Lwt.t
          val close : 'a t -> unit Lwt.t
          type hash =
              Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Node.Contents.hash
          val add : [> Irmin.Perms.write ] t -> value -> key Lwt.t
          val unsafe_add :
            [> Irmin.Perms.write ] t -> hash -> value -> key Lwt.t
          val index : [> Irmin.Perms.read ] t -> hash -> key option Lwt.t
          val clear : 'a t -> unit Lwt.t
          val batch :
            Irmin.Perms.read t ->
            ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
          module Key :
            sig
              type t = key
              val t : t Repr__Type.t
              type nonrec hash = hash
              val to_hash : t -> hash
            end
          val merge :
            [> Irmin.Perms.read_write ] t -> key option Irmin.Merge.t
          module Val :
            sig
              type t = value
              val t : t Repr__Type.t
              val merge : t option Irmin.Merge.t
            end
          module Hash :
            sig
              type t = hash
              type nonrec value = value
              val hash : value -> t
              val short_hash : t -> int
              val hash_size : int
              val t : t Repr__Type.t
            end
        end
    end
  module Node_portable :
    sig
      type t =
          Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Node_portable.t
      val t : t Repr__Type.t
      val metadata_t : unit Repr__Type.t
      type contents_key = Hash.t
      val contents_key_t : contents_key Repr__Type.t
      type node_key = Hash.t
      val node_key_t : node_key Repr__Type.t
      val step_t : string Repr__Type.t
      type value = [ `Contents of contents_key * unit | `Node of node_key ]
      val value_t : value Repr__Type.t
      val hash_t : Hash.t Repr__Type.t
      val of_list : (string * value) list -> t
      val list :
        ?offset:int ->
        ?length:int -> ?cache:bool -> t -> (string * value) list
      val of_seq : (string * value) Irmin__Import.Seq.t -> t
      val seq :
        ?offset:int ->
        ?length:int ->
        ?cache:bool -> t -> (string * value) Irmin__Import.Seq.t
      val empty : unit -> t
      val is_empty : t -> bool
      val length : t -> int
      val clear : t -> unit
      val find : ?cache:bool -> t -> string -> value option
      val add : t -> string -> value -> t
      val remove : t -> string -> t
      module Metadata :
        sig
          type t = unit
          val t : t Repr__Type.t
          val default : t
          val merge : t Irmin.Merge.t
        end
      val merge :
        contents:contents_key option Irmin.Merge.t ->
        node:node_key option Irmin.Merge.t -> t Irmin.Merge.t
      val of_node : Node.value -> t
    end
  module Commit :
    sig
      type 'a t =
          'a
          Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.t
      type key = Store_.Store2.commit_key
      type value =
          Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.value
      val mem : [> Irmin.Perms.read ] t -> key -> bool Lwt.t
      val find : [> Irmin.Perms.read ] t -> key -> value option Lwt.t
      val close : 'a t -> unit Lwt.t
      type hash = Hash.t
      val add : [> Irmin.Perms.write ] t -> value -> key Lwt.t
      val unsafe_add : [> Irmin.Perms.write ] t -> hash -> value -> key Lwt.t
      val index : [> Irmin.Perms.read ] t -> hash -> key option Lwt.t
      val clear : 'a t -> unit Lwt.t
      val batch :
        Irmin.Perms.read t -> ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
      module Key :
        sig
          type t = key
          val t : t Repr__Type.t
          type nonrec hash = hash
          val to_hash : t -> hash
        end
      module Info :
        sig
          type author = string
          val author_t : author Repr__Type.t
          type message = author
          val message_t : author Repr__Type.t
          type t = Schema.Info.t
          val t : t Repr__Type.t
          val v : ?author:message -> ?message:message -> int64 -> t
          val date : t -> int64
          val author : t -> message
          val message : t -> message
          val empty : t
          type f = unit -> t
          val none : f
        end
      module Val :
        sig
          type t = value
          val t : t Repr__Type.t
          type node_key = Node.key
          val node_key_t : node_key Repr__Type.t
          type commit_key = key
          val commit_key_t : commit_key Repr__Type.t
          val v :
            info:Info.t -> node:node_key -> parents:commit_key list -> t
          val node : t -> node_key
          val parents : t -> commit_key list
          val info : t -> Info.t
        end
      module Hash :
        sig
          type t = hash
          type nonrec value = value
          val hash : value -> t
          val short_hash : t -> int
          val hash_size : int
          val t : t Repr__Type.t
        end
      module Node :
        sig
          type 'a t =
              'a
              Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.Node.t
          type key = Val.node_key
          type value =
              Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.Node.value
          val mem : [> Irmin.Perms.read ] t -> key -> bool Lwt.t
          val find : [> Irmin.Perms.read ] t -> key -> value option Lwt.t
          val close : 'a t -> unit Lwt.t
          type hash =
              Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.Node.hash
          val add : [> Irmin.Perms.write ] t -> value -> key Lwt.t
          val unsafe_add :
            [> Irmin.Perms.write ] t -> hash -> value -> key Lwt.t
          val index : [> Irmin.Perms.read ] t -> hash -> key option Lwt.t
          val clear : 'a t -> unit Lwt.t
          val batch :
            Irmin.Perms.read t ->
            ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
          module Key :
            sig
              type t = key
              val t : t Repr__Type.t
              type nonrec hash = hash
              val to_hash : t -> hash
            end
          module Path :
            sig
              type t =
                  Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.Node.Path.t
              type step =
                  Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.Node.Path.step
              val empty : t
              val v : step list -> t
              val is_empty : t -> bool
              val cons : step -> t -> t
              val rcons : t -> step -> t
              val decons : t -> (step * t) option
              val rdecons : t -> (t * step) option
              val map : t -> (step -> 'a) -> 'a list
              val t : t Repr__Type.t
              val step_t : step Repr__Type.t
            end
          val merge :
            [> Irmin.Perms.read_write ] t -> key option Irmin.Merge.t
          module Metadata :
            sig
              type t =
                  Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.Node.Metadata.t
              val t : t Repr__Type.t
              val default : t
              val merge : t Irmin.Merge.t
            end
          module Val :
            sig
              type t = value
              val t : t Repr__Type.t
              type metadata = Metadata.t
              val metadata_t : metadata Repr__Type.t
              type contents_key =
                  Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.Node.Val.contents_key
              val contents_key_t : contents_key Repr__Type.t
              type node_key = key
              val node_key_t : node_key Repr__Type.t
              type step = Path.step
              val step_t : step Repr__Type.t
              type value =
                  [ `Contents of contents_key * metadata | `Node of node_key
                  ]
              val value_t : value Repr__Type.t
              type nonrec hash = hash
              val hash_t : hash Repr__Type.t
              val of_list : (step * value) list -> t
              val list :
                ?offset:int ->
                ?length:int -> ?cache:bool -> t -> (step * value) list
              val of_seq : (step * value) Irmin__Import.Seq.t -> t
              val seq :
                ?offset:int ->
                ?length:int ->
                ?cache:bool -> t -> (step * value) Irmin__Import.Seq.t
              val empty : unit -> t
              val is_empty : t -> bool
              val length : t -> int
              val clear : t -> unit
              val find : ?cache:bool -> t -> step -> value option
              val add : t -> step -> value -> t
              val remove : t -> step -> t
              module Metadata :
                sig
                  type t = metadata
                  val t : t Repr__Type.t
                  val default : t
                  val merge : t Irmin.Merge.t
                end
              val merge :
                contents:contents_key option Irmin.Merge.t ->
                node:node_key option Irmin.Merge.t -> t Irmin.Merge.t
            end
          module Hash :
            sig
              type t = hash
              type nonrec value = value
              val hash : value -> t
              val short_hash : t -> int
              val hash_size : int
              val t : t Repr__Type.t
            end
          module Contents :
            sig
              type 'a t =
                  'a
                  Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.Node.Contents.t
              type key = Val.contents_key
              type value =
                  Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.Node.Contents.value
              val mem : [> Irmin.Perms.read ] t -> key -> bool Lwt.t
              val find : [> Irmin.Perms.read ] t -> key -> value option Lwt.t
              val close : 'a t -> unit Lwt.t
              type hash =
                  Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit.Node.Contents.hash
              val add : [> Irmin.Perms.write ] t -> value -> key Lwt.t
              val unsafe_add :
                [> Irmin.Perms.write ] t -> hash -> value -> key Lwt.t
              val index : [> Irmin.Perms.read ] t -> hash -> key option Lwt.t
              val clear : 'a t -> unit Lwt.t
              val batch :
                Irmin.Perms.read t ->
                ([ `Read | `Write ] t -> 'a Lwt.t) -> 'a Lwt.t
              module Key :
                sig
                  type t = key
                  val t : t Repr__Type.t
                  type nonrec hash = hash
                  val to_hash : t -> hash
                end
              val merge :
                [> Irmin.Perms.read_write ] t -> key option Irmin.Merge.t
              module Val :
                sig
                  type t = value
                  val t : t Repr__Type.t
                  val merge : t option Irmin.Merge.t
                end
              module Hash :
                sig
                  type t = hash
                  type nonrec value = value
                  val hash : value -> t
                  val short_hash : t -> int
                  val hash_size : int
                  val t : t Repr__Type.t
                end
            end
        end
      val merge :
        [> Irmin.Perms.read_write ] t ->
        info:Info.f -> key option Irmin.Merge.t
    end
  module Commit_portable :
    sig
      val hash_t : Hash.t Repr__Type.t
      type t =
          Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Commit_portable.t
      val t : t Repr__Type.t
      type node_key = Hash.t
      val node_key_t : node_key Repr__Type.t
      type commit_key = Hash.t
      val commit_key_t : commit_key Repr__Type.t
      module Info :
        sig
          type author = string
          val author_t : author Repr__Type.t
          type message = author
          val message_t : author Repr__Type.t
          type t = Schema.Info.t
          val t : t Repr__Type.t
          val v : ?author:message -> ?message:message -> int64 -> t
          val date : t -> int64
          val author : t -> message
          val message : t -> message
          val empty : t
          type f = unit -> t
          val none : f
        end
      val v : info:Info.t -> node:node_key -> parents:commit_key list -> t
      val node : t -> node_key
      val parents : t -> commit_key list
      val info : t -> Info.t
      val of_commit : Commit.value -> t
    end
  module Branch :
    sig
      type t =
          Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Branch.t
      type key = string
      type value = Commit.key
      val mem : t -> key -> bool Lwt.t
      val find : t -> key -> value option Lwt.t
      val set : t -> key -> value -> unit Lwt.t
      val test_and_set :
        t -> key -> test:value option -> set:value option -> bool Lwt.t
      val remove : t -> key -> unit Lwt.t
      val list : t -> key list Lwt.t
      type watch =
          Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Branch.watch
      val watch :
        t ->
        ?init:(key * value) list ->
        (key -> value Irmin__Atomic_write_intf.diff -> unit Lwt.t) ->
        watch Lwt.t
      val watch_key :
        t ->
        key ->
        ?init:value ->
        (value Irmin__Atomic_write_intf.diff -> unit Lwt.t) -> watch Lwt.t
      val unwatch : t -> watch -> unit Lwt.t
      val clear : t -> unit Lwt.t
      val close : t -> unit Lwt.t
      module Key :
        sig
          type t = key
          val t : t Repr__Type.t
          val main : t
          val is_valid : t -> bool
        end
      module Val :
        sig
          type t = value
          val t : t Repr__Type.t
          type hash =
              Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Branch.Val.hash
          val to_hash : t -> hash
        end
    end
  module Slice :
    sig
      type t = Store_.Store2.slice
      val t : t Repr__Type.t
      type contents = Contents.hash * string
      val contents_t : contents Repr__Type.t
      type node = Node.hash * Node.value
      val node_t : node Repr__Type.t
      type commit = Commit.hash * Commit.value
      val commit_t : commit Repr__Type.t
      type value =
          [ `Commit of commit | `Contents of contents | `Node of node ]
      val value_t : value Repr__Type.t
      val empty : unit -> t Lwt.t
      val add : t -> value -> unit Lwt.t
      val iter : t -> (value -> unit Lwt.t) -> unit Lwt.t
    end
  module Repo :
    sig
      type t = Store_.Store2.repo
      val v : Irmin.config -> t Lwt.t
      val close : t -> unit Lwt.t
      val contents_t : t -> Irmin.Perms.read Contents.t
      val node_t : t -> Irmin.Perms.read Node.t
      val commit_t : t -> Irmin.Perms.read Commit.t
      val branch_t : t -> Branch.t
      val batch :
        t ->
        (Irmin.Perms.read_write Contents.t ->
         Irmin.Perms.read_write Node.t ->
         Irmin.Perms.read_write Commit.t -> 'a Lwt.t) ->
        'a Lwt.t
    end
  module Remote :
    sig
      type t =
          Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String).Backend.Remote.t
      type commit = Commit.key
      type branch = string
      type endpoint = Store_.Store1.endpoint
      val fetch :
        t ->
        ?depth:int ->
        endpoint ->
        branch -> (commit option, [ `Msg of branch ]) result Lwt.t
      val push :
        t ->
        ?depth:int ->
        endpoint ->
        branch -> (unit, [ `Detached_head | `Msg of branch ]) result Lwt.t
      val v : Repo.t -> t Lwt.t
    end
end


(** {2 Irmin_pack.Ext} *)

(* module X1 = Irmin_pack.Ext  - Ext is hidden, but intf is 

module Maker (_ : Conf.S) : S.Maker_persistent

S.Maker_persistent is Irmin_pack.S.Maker_persistent
*)



(** {2 Irmin_pack.Checks} *)

module X699 = Irmin_pack.Checks
(*
sig
  type integrity_error = [ `Absent_value | `Wrong_hash ]
  type nonrec empty = Checks.empty
  val setup_log : unit Cmdliner.Term.t
  val path : string Cmdliner.Term.t
  module type Subcommand = Checks.Subcommand
  module type S = Checks.S
  module Make = Irmin_pack.Checks.Make  - which is of type S
  module Index = Irmin_pack.Checks.Index - provides "integrity_check"
  module Stats = Irmin_pack.Checks.Stats - FIXME not sure what this is supposed to do
end

Sigs defined as: 

module type Sigs = sig
  type integrity_error = [ `Wrong_hash | `Absent_value ]
  type nonrec empty = empty

  val setup_log : unit Cmdliner.Term.t
  val path : string Cmdliner.Term.t

  module type Subcommand = Subcommand
  module type S = S

  module Make (_ : Store) : S

  module Index (Index : Pack_index.S) : sig
    val integrity_check :
      ?ppf:Format.formatter ->
      auto_repair:bool ->
      check:
        (kind:[> `Commit | `Contents | `Node ] ->
        offset:int63 ->
        length:int ->
        Index.key ->
        (unit, [< `Absent_value | `Wrong_hash ]) result) ->
      Index.t ->
      ( [> `Fixed of int | `No_error ],
        [> `Cannot_fix of string | `Corrupted of int ] )
      result
  end

  module Stats (S : sig
    type step

    val step_t : step Irmin.Type.t

    module Hash : Irmin.Hash.S
  end) : sig
    type t

    val v : unit -> t
    val visit_commit : t -> S.Hash.t -> unit
    val visit_contents : t -> S.Hash.t -> unit

    val visit_node :
      t ->
      S.Hash.t ->
      (S.step option
      * [ `Contents of S.Hash.t | `Inode of S.Hash.t | `Node of S.Hash.t ])
      list ->
      nb_children:int ->
      width:int ->
      unit

    val pp_results : dump_blob_paths_to:string option -> t -> unit
  end
end


*)


module type X774 = Irmin_pack__.Checks_intf.S
(* defined as

module type S = sig
  (** Reads basic metrics from an existing store and prints them to stdout. *)
  module Stat : sig
    include Subcommand with type run := root:string -> unit Lwt.t

    (** Internal implementation utilities exposed for use in other integrity
        checks. *)

    type size = Bytes of int [@@deriving irmin]

    type io = { size : size; offset : int63; version : Version.t }
    [@@deriving irmin]

    type files = { pack : io option; branch : io option; dict : io option }
    [@@deriving irmin]

    type objects = { nb_commits : int; nb_nodes : int; nb_contents : int }
    [@@deriving irmin]

    val v : root:string -> files
    val traverse_index : root:string -> int -> objects
  end

  module Reconstruct_index :
    Subcommand
      with type run :=
            root:string ->
            output:string option ->
            ?index_log_size:int ->
            unit ->
            unit
  (** Rebuilds an index for an existing pack file *)

  (** Checks the integrity of a store *)
  module Integrity_check : sig
    include
      Subcommand with type run := root:string -> auto_repair:bool -> unit Lwt.t

    val handle_result :
      ?name:string ->
      ( [< `Fixed of int | `No_error ],
        [< `Cannot_fix of string | `Corrupted of int ] )
      result ->
      unit
  end

  (** Checks the integrity of the index in a store *)
  module Integrity_check_index : sig
    include
      Subcommand
        with type run := root:string -> auto_repair:bool -> unit -> unit
  end

  (** Checks the integrity of inodes in a store *)
  module Integrity_check_inodes : sig
    include
      Subcommand
        with type run := root:string -> heads:string list option -> unit Lwt.t
  end

  (** Traverses a commit to get stats on its underlying tree. *)
  module Stats_commit : sig
    include
      Subcommand
        with type run :=
              root:string ->
              commit:string option ->
              dump_blob_paths_to:string option ->
              unit ->
              unit Lwt.t
  end

  val cli :
    ?terms:(unit Cmdliner.Term.t * Cmdliner.Term.info) list -> unit -> empty
  (** Run a [Cmdliner] binary containing tools for running offline checks.
      [terms] defaults to the set of checks in this module. *)
end
*)



(** {2 How to extract the Pack_store after making a Store?} *)

(* Pack_store has the debug_io *)

(* Suppose we do Irmin_pack.KV(Store_.Conf).Make(Irmin.Contents.String); what does this consist of? Essentially

In irmin_pack.ml:

module KV (Config : Conf.S) = struct
  type endpoint = unit
  type hash = Irmin.Schema.default_hash

  include Pack_key.Store_spec
  module Maker = Maker (Config)

  type metadata = Metadata.t

  module Make (C : Irmin.Contents.S) = Maker.Make (Irmin.Schema.KV (C))
end

And Maker is defined in Ext

*)


(** {2 irmin-pack keys, accessing offsets...}

From pack_key_intf.ml

  (** The internal state of a key (read with {!inspect}).

      Invariant: keys of the form {!Indexed} always reference values that have
      entries in the index (as otherwise these keys could not be dereferenced). *)
  type 'hash state = private
    | Direct of { hash : 'hash; offset : int63; length : int }
        (** A "direct" pointer to a value stored at [offset] in the pack-file
            (with hash [hash] and length [length]). Such keys can be
            dereferenced from the store with a single IO read, without needing
            to consult the index.

            They are built in-memory (e.g. after adding a fresh value to the
            pack file), but have no corresponding encoding format, as the pack
            format keeps length information with the values themselves.

            When decoding a inode, which references its children as single
            offsets, we fetch the length information of the child at the same
            time as fetching its hash (which we must do anyway in order to do an
            integrity check), creating keys of this form. *)
    | Indexed of 'hash
        (** A pointer to an object in the pack file that is indexed. Reading the
            object necessitates consulting the index, after which the key can be
            promoted to {!Direct}.

            Such keys result from decoding pointers to other store objects
            (nodes or commits) from commits or from the branch store. *)

So, direct keys have the (off,len) info which is obv very useful

Let's suppose we have a commit value. How can we traverse the tree for that commit? Irmin Commit_intf has:

  val v : info:Info.t -> node:node_key -> parents:commit_key list -> t
  (** Create a commit. *)

  val node : t -> node_key
  (** The underlying node key. *)

ie we create a commit based on a node(node_key), and from a commit, we can get a node_key

So, what about the root node? Can we get the offset? Yes, if node_key is a direct
pack_key. So what about the objects reffed from the node? We can use the node list function to get the (step,value) list; value is either node node_key or contents contents_key * metadata (is the meta stored with the contents?); 

OK, so then we can go from node_key to off,len? Except that a node is implemented by a collection of inodes. So what does off,len mean for a node?

TODO pack_value has encoding for a node... 

Let's look at encoding quickly: 

    module V1 = struct
      type data = { length : int; v : Commit_direct.t } [@@deriving irmin]
      type t = (hash, data) value [@@deriving irmin ~encode_bin ~decode_bin]
    end


has sig

sig
  type data = { length : int; v : Commit_direct.t; }
  val data_t : data Repr.ty
  type t = (hash, data) value
  val t : (hash, data) value Repr.ty
  val encode_bin : (hash, data) value Repr.encode_bin
  val decode_bin : (hash, data) value Repr.decode_bin
end

so [@@deriving irmin] gives value data_t of type data Repr.ty ... which is a value that
represents the data type; and presumably we can get encode_bin and decode_bin from there?
where is doc for repr?




*)

type x = int Repr.ty

type y = int Repr.encode_bin (* type 'a encode_bin = 'a -> (string -> unit) -> unit *)

(* ie 'a encode_bin takes an 'a and a string sink, and shoves lots of strings to the sink *)


(*

Representing node as inode: ext.ml has

      module Node = struct
        module Value = Schema.Node (XKey) (XKey)

        module CA = struct
          module Inter = Inode.Make_internal (Config) (H) (XKey) (Value)
          include Inode.Make_persistent (H) (Value) (Inter) (Pack)
        end

        include
          Irmin.Node.Generic_key.Store (Contents) (CA) (H) (CA.Val) (M) (P)
      end



*)


(* ok, looking at inode_intf to see if that gives any clues ... 


We have: 

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
end

Which has the decode_bin_length function, but not the serialization functions!

*)
