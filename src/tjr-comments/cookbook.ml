(** A cookbook of Irmin recipes *)

(** {1 Existing tests} 

{2 test/irmin}

[test_tree.ml] seems the most interesting; uses Irmin_mem

*)


(** {1 Cookbook} *)

module P = struct
  include Printf
  let p = printf
  let s = sprintf
end

module F = struct
  include Format
  let p = printf
  let s = sprintf
end

(** {2 Opening an in-mem store and adding some stuff} *)

open Irmin

module Private_1() = struct
  (* want to use Irmin_mem.Make(Schema) *)

  module Make = Irmin_mem.Make

  (** Metadata is a type and a way to 3-way merge two metas with a common ancestor *)
  module Metadata = struct
    type t = My_metadata[@@deriving irmin]
    let default = My_metadata
    let merge : t Merge.t = Merge.v t (fun ~old x y -> Lwt.return (Ok My_metadata))
  end[@@warning "-27"]

  module Schema = struct
    module Metadata = Metadata 
    module Contents = Contents.String
    module Path = Path.String_list
    module Branch = Branch.String
    (* defines a type, and a main value of that type, and a predicate "is_valid" (why?) *)
    module Hash = Hash.BLAKE2B (* lots of options *)
    module Node = Node.Generic_key.Make(Hash)(Path)(Metadata)
    (* Node: Path includes a notion of step; step has not been pulled out as a separate
       module; NOTE Node is now a functor from contents_key -> Node_key -> ... *)
    module Commit = Commit.Make(Hash) 
    (* NOTE Commit also includes an Info submodule with type t= Info.Default.t; probably
       there is only ever one Info *)
    module Info = Info.Default (* author, message, date as int64 *)      
  end

  module Store = Irmin_mem.Make(Schema)
  (* mostly types we already understand; also slice_t... contents_key and node key are now
     hashes; commit_key is a hash

     interesting submodules: Repo, Head, Commit, Tree, History, Branch, Backend,
     Backend.Node_portable, Backend.Slice, Backend.Repo (same as Store.Repo?)

     (these modules may be named as the Schema modules, but include a lot more functionality)

     funs: status: Store.t -> Status.t; lots of functions at top-level of Store


     save_contents, save_tree give back a key, presumably forcing indexing?
  *)

  (* abbrev *)
  module S = Store
  module Repo_ = S.Repo
  module Tree_ = S.Tree

  let meta_ = Metadata.My_metadata

  (* can create trees freely, without a store or repo *)

  let tree : S.tree = 
    Tree_.of_concrete 
      (`Tree [
          "a",`Contents("hello",meta_);
          "b",`Contents("world",meta_);
          "c",`Tree []
        ])

  let _ = 
    let pp = Type.pp_dump S.tree_t in
    F.p "The tree is: %a\n" pp tree;
    ()
  (* Prints: The tree is: Node ({"map":[["b",{"Contents":{"value":"world"}}],["a",{"Contents":{"value":"hello"}}]]}) 

     NOTE the Node is a map, but could? be other things?
  *)  

  (* getting a repo, then a store *)

  open Lwt.Infix

  let repo : Repo_.t Lwt.t = Store.Repo.v (Irmin_mem.config ())

  (* we cant pp a repo; but we can print the commit list... *)

  module C_list = struct
    (* type t = S.commit list[@@deriving irmin] - val commit_t takes a repo arg; so commit_t
       only exists once we select a repo *)
  end

  (* probably there aren't any heads at this stage *)
  let print_repo repo : unit Lwt.t = 
    repo >>= fun repo -> 
    Repo_.heads repo >>= fun cs -> 
    P.p "Repo heads: ";
    begin
      List.iter (fun c -> 
          let pp = S.Commit.pp_hash in
          F.p "(Commit hash: %a) " pp c) cs 
    end;
    P.p "\n";
    Lwt.return ()

  let _ = print_repo repo

  let store : S.t Lwt.t = repo >>= fun repo -> Store.empty repo

  (* saving a tree to a store *)

  (* default info; a function for some reason *)
  let info = S.Info.none

  let save_tree : unit Lwt.t = 
    store >>= fun store -> 
    S.set_tree_exn ~info store [] tree >>= fun () -> 
    P.p "finished save_tree\n"; Lwt.return ()

  (* so the tree should now be associated with the store *)

  let _ = save_tree >>= fun () -> print_repo repo
  (* tree is not one of the repo head commits - we haven't done that yet *)

  (* # Iterate over repo *)

  (* need a node key *)
  let nk = 
    tree |> Tree_.key |> function
    | Some (`Node nk) -> nk
    | _ -> failwith "nk"

  let _ = repo >>= fun repo -> 
    P.p "Iterating over repo\n";
    Repo_.iter 
      ~min:[] 
      ~max:[`Node nk] 
      ~contents:(fun k -> 
          F.p "Repo.iter: contents %a\n" (Type.pp_dump S.contents_key_t) k; Lwt.return ()) repo 
(*
Iterating over repo
Repo.iter: contents e4cfa39a3d37be31c59609e807970799caa68a19bfaa15135f165085e01d41a65ba1e1b146aeb6bd0092b49eac214c103ccfa3a365954bbbe52f74a2b3620c94
Repo.iter: contents 267b2e02b6af3d5bff52397f238c3a240e5d1319375dc5c60ef9f0df5ae9511761968f33a2ce17a0952d85fed231e6103c867f0432c250dd52baf959c7fc4759

e4cf is the blake2b hash for "hello" - listed many times on google; echo -n hello | b2sum

267b2e is for "world"
*)

  (* # Creating a commit *)

  let commit = 
    repo >>= fun repo -> S.Commit.v repo ~info:(info()) ~parents:[] tree

  let _ = 
    repo >>= fun repo -> 
    commit >>= fun commit -> 
    F.p "Commit: %a\n" (Type.pp_dump (S.commit_t repo)) commit;
    Lwt.return ()
(*

Commit: 
{ key =
   8cb1e6bd713e7b25f9b3edf78b0f9dbe9b81797a7b8c9e9c553746b79c38e6a997ff5ef95a24cb434e8fbdc43e08ffb231011bbaa46d1b7b389ec181678a10f7;
  value =
   { node =
      9115266953427f63c1028b6947700043aa4355527debc123fe7f573ff780fc73d16938d02b61d1b9f32789b2187c711709c7c83108f097ded1e6b73ee891f792;
     parents = [];
     info = { date = 0;
              author = "";
              message = "" } } }
*)

  let commit_key = 
    commit >>= fun commit -> 
    S.Commit.key commit |> fun k -> 
    Lwt.return k 

  (* but we want to convert from a string perhaps *)

  (* commit_key doesn't seem to have many functions... so we have to go from commit to
     hash *)

  let commit_hash = 
    commit >>= fun commit -> 
    S.Commit.hash commit |> fun h -> 
    F.p "Key has hash: %a\n" (Type.pp_dump S.hash_t) h;
    Lwt.return h
  (* 
Key has hash: 8cb1e6bd713e7b25f9b3edf78b0f9dbe9b81797a7b8c9e9c553746b79c38e6a997ff5ef95a24cb434e8fbdc43e08ffb231011bbaa46d1b7b389ec181678a10f7
*)

  let hash_s = 
    commit_hash >>= fun h -> 
    let s = Type.to_string S.hash_t h in
    P.p "Hash as string: %s\n" s;
    Lwt.return s
(*
Hash as string: 8cb1e6bd713e7b25f9b3edf78b0f9dbe9b81797a7b8c9e9c553746b79c38e6a997ff5ef95a24cb434e8fbdc43e08ffb231011bbaa46d1b7b389ec181678a10f7
*)

  (* try to recover commit from hash *)

  let h_to_c =
    repo >>= fun repo ->
    hash_s >>= fun s -> 
    let Ok h = Type.of_string S.hash_t s in
    S.Commit.of_hash repo h >>= function
    | Some c -> Lwt.return c
  [@@warning "-8"]

  let _ = 
    repo >>= fun repo ->
    h_to_c >>= fun c -> 
    F.p "Commit: %a\n" (Type.pp_dump (S.commit_t repo)) c;
    Lwt.return ()
  (* successfully finds commit *)

  let _ = Lwt_main.run save_tree
end

(** {1 Irmin-pack} *)

(* We now try the same experiments, using irmin-pack *)

open Lwt.Infix
    
let ( / ) = Filename.concat

(* First, manually copy a store test/irmin-pack/data/version_1 to /tmp *)

let _ = assert(Sys.file_exists "/tmp/version_1")

(* see test_pack_version_bump.ml *)

module Conf = Irmin_tezos.Conf
module Schema = struct
  open Irmin
  module Metadata = Metadata.None
  module Contents = Contents.String
  module Path = Path.String_list
  module Branch = Branch.String
  module Hash = Hash.SHA1
  module Node = Node.Generic_key.Make (Hash) (Path) (Metadata)
  module Commit = Commit.Generic_key.Make (Hash)
  module Info = Info.Default
end

module Maker_ = Irmin_pack.Maker(Conf)
(*
  type 'h node_key = 'h Irmin_pack.Pack_key.t
  type 'h commit_key = 'h node_key



*)
module X = Maker_


module S = Maker_.Make(Schema)

let fn = "/tmp/version_1"

let config = Irmin_pack.config ~readonly:true fn

let repo = S.Repo.v config

(* NOTE we redefine, because the Repo.t type is different *)
let print_repo repo : unit Lwt.t = 
  repo >>= fun repo -> 
  S.Repo.heads repo >>= fun cs -> 
  P.p "Repo heads: ";
  begin
    List.iter (fun c -> 
        let pp = S.Commit.pp_hash in
        F.p "(Commit hash: %a) " pp c) cs 
  end;
  P.p "\n";
  Lwt.return ()

let go = print_repo repo
(*
Repo heads: (Commit hash: bcb476cc35e5f46932ca9761f048f312145fed10) (Commit hash: c6ed25ff0bc10b7112c257998c0cbbe71982871c) 
*)

let _ = 
  repo >>= fun repo -> 
  S.Repo.branches repo >>= fun bs -> 
  P.p "Branches: %s\n" (String.concat " " bs);
  Lwt.return ()
(*
Branches: foo bar
*)

let commit = 
  repo >>= fun repo ->
  S.Branch.get repo "foo" >>= fun c -> 
  Lwt.return c

let _ = 
  repo >>= fun repo ->
  commit >>= fun c ->
  F.p "Got head commit: %a\n" (Type.pp_dump (S.commit_t repo)) c;
  Lwt.return ()

(*
Got head commit: 
{ key = {"Direct":["c6ed25ff0bc10b7112c257998c0cbbe71982871c",408,52]};
  value =
   { node = {"Indexed":"e40af3267e92203b17eba902aa6665d554e334ae"};
     parents = [];
     info = { date = 0;
              author = "";
              message = "" } } }
*)

(* NOTE that we can apparently see that the commit is stored at offset 408, and is of
   length 52 *)

(* print tree *)
let tree = 
  commit >>= fun c ->
  let tree = S.Commit.tree c in
  Lwt.return tree

let _ = 
  tree >>= fun tree -> 
  F.p "Tree: %a\n" (Type.pp_dump S.tree_t) tree;
  Lwt.return ()
(*
Tree: Node ({"key":{"Indexed":"e40af3267e92203b17eba902aa6665d554e334ae"}})
*)

(* So, to see the full tree, we either get from index - FIXME TODO - or convert to
   concrete... *)

let _ =
  tree >>= fun t -> 
  S.Tree.to_concrete t >>= fun ct ->
  F.p "Concrete tree: %a\n" (Type.pp_dump S.Tree.concrete_t) ct;
  Lwt.return ()
(*
Concrete tree: Tree 
([("b", Contents (("y", ())))])

ie a tree with a single child under name "b", with contents "y"
*)

(* fair enough; now we want to find the off,len info for the tree node... *)

let nk = 
  tree >>= fun tree ->
  (* the tree is a Node ({"key":{"Indexed":"e40af3267e92203b17eba902aa6665d554e334ae"}})
     but how to work with this? node_key is a hash Irmin_pack.Pack_key.t... *)
  S.Tree.key tree |> function Some (`Node nk) -> 
    F.p "Node key: %a\n" (Type.pp_dump S.node_key_t) nk;
    Lwt.return (nk : S.hash Maker_.node_key)
[@@warning "-8"]
(*
Node key: {"Direct":["e40af3267e92203b17eba902aa6665d554e334ae",374,34]}

So, this is telling us that the node is an object stored at off,len 374,34, which is the
region just before the commit

Can we access the parts of the node key?

nk is of type (S.hash Maker_.node_key) = (S.hash Irmin_pack.Pack_key.t)
*)    
  
module Pk = Irmin_pack.Pack_key
(* and note the function: val inspect : 'hash t -> 'hash state, which allows to inspect
   the nk

So, how can we use this pack key to get hold of an object?

Also, this is talking in terms of node, but we know that nodes are implemented by inodes;
so what does it mean that a node is stored as reg. 374,34? That this is the location of
the root inode?

TODO could look at snapshot export code, or existing layered store code?

The irmin/store.ml code is parameterized by a backend, which is presumably used by
irmin-pack... how does irmin-pack use the inode code?

*)


(** {2 off,len in pack_key, and where it enters the irmin-pack ecosystem} 

The interesting thing is that off,len info is exposed at the irmin-API level; so would be
good to see how that info arises eg via S.Tree.key tree (an in-mem tree then gets flushed
to disk?)

tree.ml defines type t = node | contents, where these are Backend node/content types

tree.ml defines Node as (v,info), which v either Map, Key, Value or Pruned; inspect reveals this info;

[[file:/tmp/l/github/irmin-worktree-doc/src/irmin/tree.ml::let%20key%20(t%20:%20t)%20=]]

org-open-link-from-string
org-store-link
org-insert-link

*)


(** {2 Using Repo.iter or fold, and inspecting the pack key... } *)

module Repo = S.Repo

let _ = 
  Printf.printf "Using Repo.iter\n%!";
  repo >>= fun repo -> 
  commit >>= fun commit -> 
  S.Commit.key commit |> fun commit_key ->
  S.Repo.iter 
    ~min:[] ~max:[`Commit commit_key] 
    ~commit:(fun k -> 
        begin
          let k' = Pk.inspect k in
          match k' with
          | Indexed _ -> Printf.printf "Commit: got indexed key\n"
          | Direct {hash=_;offset;length} -> 
            Printf.printf "Commit: got direct key (off,len)=(%d,%d)\n" (Optint.Int63.to_int offset) length;
        end;
        Lwt.return ())
    ~node:(fun k -> 
        begin
          let k' = Pk.inspect k in
          match k' with
          | Indexed _ -> Printf.printf "Node: got indexed key\n"
          | Direct {hash=_;offset;length} -> 
            Printf.printf "Node: got direct key (off,len)=(%d,%d)\n" (Optint.Int63.to_int offset) length;
        end;
        Lwt.return ())
    ~contents:(fun k -> 
        begin
          let k' = Pk.inspect k in
          match k' with
          | Indexed _ -> Printf.printf "Contents: got indexed key\n"
          | Direct {hash=_;offset;length} -> 
            Printf.printf "Contents: got direct key (off,len)=(%d,%d)\n" (Optint.Int63.to_int offset) length;
        end;
        Lwt.return ())
    repo


(** {2 For layered, want to pass a schema and a path and a commit key as a string, then call Repo.iter to calculate the reachability} *)



let _ = Lwt_main.run go
