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
module IO = IO.Unix

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
    module Dict = Pack_dict
    module XKey = Pack_key.Make (H)

    module X = struct
      module Hash = H

      type 'a value = { hash : H.t; kind : Pack_value.Kind.t; v : 'a }
      [@@deriving irmin]

      module Contents = struct
        module Pack_value = Pack_value.Of_contents (Config) (H) (XKey) (C)
        module CA = Pack.Make (Pack_value)
        include Irmin.Contents.Store_indexable (CA) (H) (C)
      end

      module Node = struct
        module Value = Schema.Node (XKey) (XKey)

        module CA = struct
          module Inter =
            Irmin_pack.Inode.Make_internal (Config) (H) (XKey) (Value)

          include Inode.Make_persistent (H) (Value) (Inter) (Pack)
        end

        include
          Irmin.Node.Generic_key.Store (Contents) (CA) (H) (CA.Val) (M) (P)
      end

      module Node_portable = Node.CA.Val.Portable

      module Schema = struct
        include Schema
        module Node = Node
      end

      module Commit = struct
        module Value = struct
          include Schema.Commit (Node.Key) (XKey)
          module Info = Schema.Info

          type hash = Hash.t [@@deriving irmin]
        end

        module Pack_value = Pack_value.Of_commit (H) (XKey) (Value)
        module CA = Pack.Make (Pack_value)

        include
          Irmin.Commit.Generic_key.Store (Schema.Info) (Node) (CA) (H) (Value)
      end

      module Commit_portable = struct
        module Hash_key = Irmin.Key.Of_hash (Hash)
        include Schema.Commit (Hash_key) (Hash_key)

        let of_commit : Commit.Value.t -> t =
         fun t ->
          let info = Commit.Value.info t
          and node = Commit.Value.node t |> XKey.to_hash
          and parents = Commit.Value.parents t |> List.map XKey.to_hash in
          v ~info ~node ~parents

        module Info = Schema.Info

        type hash = Hash.t [@@deriving irmin]
      end

      module Branch = struct
        module Key = B
        module Val = XKey
        module AW = Atomic_write.Make_persistent (Key) (Val)
        include Atomic_write.Closeable (AW)

        let v ?fresh ?readonly path =
          AW.v ?fresh ?readonly path >|= make_closeable
      end

      module Slice = Irmin.Backend.Slice.Make (Contents) (Node) (Commit)
      module Remote = Irmin.Backend.Remote.None (Commit.Key) (B)

      module Repo = struct
        type t = {
          config : Irmin.Backend.Conf.t;
          contents : read Contents.CA.t;
          node : read Node.CA.t;
          commit : read Commit.CA.t;
          branch : Branch.t;
          index : Index.t;
        }

        let contents_t t : 'a Contents.t = t.contents
        let node_t t : 'a Node.t = (contents_t t, t.node)
        let commit_t t : 'a Commit.t = (node_t t, t.commit)
        let branch_t t = t.branch

        let batch t f =
          Commit.CA.batch t.commit (fun commit ->
              Node.CA.batch t.node (fun node ->
                  Contents.CA.batch t.contents (fun contents ->
                      let contents : 'a Contents.t = contents in
                      let node : 'a Node.t = (contents, node) in
                      let commit : 'a Commit.t = (node, commit) in
                      f contents node commit)))

        let unsafe_v config =
          let root = Conf.root config
          and fresh = Conf.fresh config
          and lru_size = Conf.lru_size config
          and readonly = Conf.readonly config
          and log_size = Conf.index_log_size config
          and throttle = Conf.merge_throttle config
          and indexing_strategy = Conf.indexing_strategy config in
          let f = ref (fun () -> ()) in
          let index =
            Index.v
              ~flush_callback:(fun () -> !f ())
                (* backpatching to add pack flush before an index flush *)
              ~fresh ~readonly ~throttle ~log_size root
          in
          let* contents =
            Contents.CA.v ~fresh ~readonly ~lru_size ~index ~indexing_strategy
              root
          in
          let* node =
            Node.CA.v ~fresh ~readonly ~lru_size ~index ~indexing_strategy root
          in
          let* commit =
            Commit.CA.v ~fresh ~readonly ~lru_size ~index ~indexing_strategy
              root
          in
          let+ branch = Branch.v ~fresh ~readonly root in
          (* Stores share instances in memory, one flush is enough. In case of a
             system crash, the flush_callback might not make with the disk. In
             this case, when the store is reopened, [integrity_check] needs to be
             called to repair the store. *)
          (f := fun () -> Contents.CA.flush ~index:false contents);
          { contents; node; commit; branch; config; index }

        let close t =
          Index.close t.index;
          Contents.CA.close (contents_t t) >>= fun () ->
          Node.CA.close (snd (node_t t)) >>= fun () ->
          Commit.CA.close (snd (commit_t t)) >>= fun () -> Branch.close t.branch

        let v config =
          Lwt.catch
            (fun () -> unsafe_v config)
            (function
              | Version.Invalid { expected; found } as e
                when expected = Version.latest ->
                  [%log.err
                    "[%s] Attempted to open store of unsupported version %a"
                      (Conf.root config) Version.pp found];
                  Lwt.fail e
              | e -> Lwt.fail e)

        (** Stores share instances in memory, one sync is enough. *)
        let sync t = Contents.CA.sync (contents_t t)

        let flush t =
          Contents.CA.flush (contents_t t);
          Branch.flush t.branch
      end
    end

    let integrity_check ?ppf ~auto_repair t =
      let module Checks = Checks.Index (Index) in
      let contents = X.Repo.contents_t t in
      let nodes = X.Repo.node_t t |> snd in
      let commits = X.Repo.commit_t t |> snd in
      let check ~kind ~offset ~length k =
        match kind with
        | `Contents -> X.Contents.CA.integrity_check ~offset ~length k contents
        | `Node -> X.Node.CA.integrity_check ~offset ~length k nodes
        | `Commit -> X.Commit.CA.integrity_check ~offset ~length k commits
      in
      Checks.integrity_check ?ppf ~auto_repair ~check t.index

    include Irmin.Of_backend (X)

    let integrity_check_inodes ?heads t =
      [%log.debug "Check integrity for inodes"];
      let counter, (_, progress_nodes, progress_commits) =
        Utils.Object_counter.start ()
      in
      let errors = ref [] in
      let nodes = X.Repo.node_t t |> snd in
      let pred_node repo key =
        Lwt.catch
          (fun () -> Repo.default_pred_node repo key)
          (fun _ ->
            errors := "Error in repo iter" :: !errors;
            Lwt.return [])
      in

      let node k =
        progress_nodes ();
        X.Node.CA.integrity_check_inodes nodes k >|= function
        | Ok () -> ()
        | Error msg -> errors := msg :: !errors
      in
      let commit _ =
        progress_commits ();
        Lwt.return_unit
      in
      let* heads =
        match heads with None -> Repo.heads t | Some m -> Lwt.return m
      in
      let hashes = List.map (fun x -> `Commit (Commit.key x)) heads in
      let+ () =
        Repo.iter ~cache_size:1_000_000 ~min:[] ~max:hashes ~pred_node ~node
          ~commit t
      in
      Utils.Object_counter.finalise counter;
      let pp_commits = Fmt.list ~sep:Fmt.comma Commit.pp_hash in
      if !errors = [] then
        Fmt.kstr (fun x -> Ok (`Msg x)) "Ok for heads %a" pp_commits heads
      else
        Fmt.kstr
          (fun x -> Error (`Msg x))
          "Inconsistent inodes found for heads %a: %a" pp_commits heads
          Fmt.(list ~sep:comma string)
          !errors

    module Stats = struct
      let pp_key = Irmin.Type.pp XKey.t

      let traverse_inodes ~dump_blob_paths_to commit repo =
        let module Stats = Checks.Stats (struct
          type nonrec step = step

          let step_t = step_t

          module Hash = Hash
        end) in
        let t = Stats.v () in
        let pred_node repo k =
          X.Node.find (X.Repo.node_t repo) k >|= function
          | None -> Fmt.failwith "key %a not found" pp_key k
          | Some v ->
              let width = X.Node.Val.length v in
              let nb_children = X.Node.CA.Val.nb_children v in
              let preds = X.Node.CA.Val.pred v in
              let () =
                preds
                |> List.map (function
                     | s, `Contents h -> (s, `Contents (XKey.to_hash h))
                     | s, `Inode h -> (s, `Inode (XKey.to_hash h))
                     | s, `Node h -> (s, `Node (XKey.to_hash h)))
                |> Stats.visit_node t (XKey.to_hash k) ~width ~nb_children
              in
              List.rev_map
                (function
                  | s, `Inode x ->
                      assert (s = None);
                      `Node x
                  | _, `Node x -> `Node x
                  | _, `Contents x -> `Contents x)
                preds
        in
        (* We are traversing only one commit. *)
        let pred_commit repo k =
          X.Commit.find (X.Repo.commit_t repo) k >|= function
          | None -> []
          | Some c ->
              let node = X.Commit.Val.node c in
              Stats.visit_commit t (XKey.to_hash node);
              [ `Node node ]
        in
        let pred_contents _repo k =
          Stats.visit_contents t (XKey.to_hash k);
          Lwt.return []
        in
        (* We want to discover all paths to a node, so we don't cache nodes
           during traversal. *)
        let* () =
          Repo.breadth_first_traversal ~cache_size:0 ~pred_node ~pred_commit
            ~pred_contents ~max:[ commit ] repo
        in
        Stats.pp_results ~dump_blob_paths_to t;
        Lwt.return_unit

      let run ~dump_blob_paths_to ~commit repo =
        Printexc.record_backtrace true;
        let key = `Commit (Commit.key commit) in
        traverse_inodes ~dump_blob_paths_to key repo
    end

    let stats = Stats.run
    let sync = X.Repo.sync
    let flush = X.Repo.flush

    module Traverse_pack_file = Traverse_pack_file.Make (struct
      module Hash = H
      module Index = Index
      module Inode = X.Node.CA
      module Dict = Dict
      module Contents = X.Contents.Pack_value
      module Commit = X.Commit.Pack_value
    end)

    let traverse_pack_file = Traverse_pack_file.run

    (* following for layers *)
    module Private_layers = struct

      let get_pack_store_io' : repo -> Pack_store_IO.t = fun repo -> 
        let contents : read X.Contents.t = repo.contents in
        let contents : read X.Contents.CA.t = contents in
        let io : Pack_store_IO.t = X.Contents.CA.get_pack_store_io contents in
        io

      (* let get_pack_store_io: (repo -> Pack_store_IO.t) option = Some get_pack_store_io' *)

      let get_config (repo:repo) : Irmin.Backend.Conf.t = repo.config

      (* NOTE the following function MUST ONLY be run in the worker process *)
      let create_reachable ~repo ~commit_hash_s = begin fun ~reachable_fn -> 
          let open struct
            let _ = assert(!Irmin_pack_layers.running_in_worker = true)

            let _ = 
              assert(Option.is_none !Irmin_pack_layers.running_create_reach_exe);
              Irmin_pack_layers.running_create_reach_exe := Some reachable_fn

            (* we need to load another copy of repo, in order to avoid interacting with
               fds from the parent process *)
            let repo = 
              let config = get_config repo in
              let root = Irmin_pack.Conf.root config in
              Repo.v (Irmin_pack.config ~readonly:true root)

            let Ok hash = Irmin.Type.of_string (*S.*)hash_t commit_hash_s[@@warning "-8"]

            let commit = 
              repo >>= fun repo -> 
              (*S.*)Commit.of_hash repo hash >>= function
              | Some c -> 
                Printf.printf "Found commit %s\n" commit_hash_s;
                Lwt.return c[@@warning "-8"]

            let finish_cb () = Lwt.return ()

            let iter = 
              repo >>= fun repo -> 
              commit >>= fun commit -> 
              Printf.printf "Calling Repo.iter\n%!";
              (*S.*)Commit.key commit |> fun commit_key ->
              (* Repo.iter takes callbacks for each particular type of object; the
                 callbacks typically take a key; we want to ensure that each particular
                 object is at least read; so for each callback we use the key to pull the
                 full object *)
              let commit_cb = fun ck -> 
                (*S.*)Commit.of_key repo ck >>= function
                | None -> failwith (Printf.sprintf "%s: commit_cb" __FILE__)
                | Some _commit -> finish_cb ()
              in
              let contents_cb = fun ck -> 
                (*S.*)Contents.of_key repo ck >>= function
                | None -> failwith (Printf.sprintf "%s: contents_cb" __FILE__)
                | Some _contents -> finish_cb ()
              in
              let node_cb = fun nk -> 
                (*S.*)Tree.of_key repo (`Node nk) >>= function
                | None -> failwith (Printf.sprintf "%s: node_cb" __FILE__)
                | Some _tree -> finish_cb()
              in
              (*S.*)Repo.iter
                ~cache_size:0
                ~min:[`Commit commit_key] ~max:[`Commit commit_key] 
                ~edge:(fun _e1 _e2 -> Lwt.return ())
                ~branch:(fun s -> ignore s; Lwt.return ())
                ~commit:commit_cb
                ~node:node_cb
                ~contents:contents_cb
                repo

            let _ = Lwt_main.run iter

            (* Pack store reads are logged to the output file; we don't have a handle on
               the [out_channel], so we can't directly close the channel; likely the
               channel is flushed and closed on termination anyway, but just to make sure,
               we flush all out channels at this point, just before termination *)
            let _ = Stdlib.flush_all ()
          end
          in
          ()
        end          
      

      (* Why does the following piece of implementation belong here?
         Pack_store_IO.trigger_gc knows nothing about [type repo] etc; so in order to
         implement a function [: repo -> string -> unit] we need to be outside
         Pack_store_IO; at least in this file, we have access to all the implementation
         parts that we could need. *)
      let trigger_gc' (repo:repo) commit_hash_s =
        let io = get_pack_store_io' repo in
        let args = Pack_store_IO.Trigger_gc.{
            commit_hash_s;
            create_reachable=(fun ~reachable_fn -> 
                create_reachable ~repo ~commit_hash_s ~reachable_fn)
          }
        in
        Pack_store_IO.trigger_gc io args;
        Pack_store.clear_all_caches ();
        ()

      let trigger_gc = Some trigger_gc'
    end

    let get_config = Private_layers.get_config
    let trigger_gc = Private_layers.trigger_gc

  end
end
