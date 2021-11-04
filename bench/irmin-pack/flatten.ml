open Irmin.Export_for_backends

module Flatten_storage_for_H
    (Store : Irmin_pack.S with type Schema.Path.t = string list) =
struct
  let data_key key = [ "data" ] @ key

  type context = { repo : Store.Repo.t; tree : Store.tree }

  let tree_fold ?depth t k ~init ~f =
    Store.Tree.find_tree t k >>= function
    | None -> Lwt.return init
    | Some t ->
        Store.Tree.fold ?depth ~force:`True ~cache:false ~uniq:`False
          ~order:`Sorted
          ~tree:(fun k t acc ->
            match Store.Tree.destruct t with
            | `Contents _ -> if k = [] then Lwt.return acc else f k t acc
            | `Node _ -> f k t acc)
          t init

  let fold ?depth ctxt key ~init ~f =
    tree_fold ?depth ctxt.tree (data_key key) ~init ~f

  (* /tree_abs_key/key/*/*/*/*/*
     => /tree_abs_key/key/rename( */*/*/*/* )
  *)
  let flatten ~tree ~key ~depth ~rename:_ ~(init : Store.tree) =
    tree_fold tree key ~depth:(`Eq depth) ~init ~f:(fun old_key tree dst_tree ->
        ignore old_key;
        ignore tree;
        Lwt.return dst_tree)
    >>= fun dst_tree ->
    (* rm -rf $index_key
       mv $tmp_index_key $index_key *)
    Lwt.return dst_tree

  (* /abs_key/*(depth')/mid_key/*(depth)
     => /abs_key/*(depth')/mid_key/rename( *(depth) )
  *)
  let fold_flatten ctxt abs_key depth' mid_key ~depth ~rename =
    fold ~depth:(`Eq depth') ctxt abs_key ~init:ctxt ~f:(fun key tree ctxt ->
        (* tree at /abs_key/*(depth') *)
        flatten ~tree ~key:mid_key ~depth ~rename ~init:(Store.Tree.empty ())
        >>= fun tree ->
        ignore key;
        Lwt.return { ctxt with tree })

  let flatten_storage ctxt =
    [%logs.info
      "flattening the context storage: this operation may take several minutes"];
    let rec drop n xs =
      match (n, xs) with
      | 0, _ -> xs
      | _, [] -> assert false
      | _, _ :: xs -> drop (n - 1) xs
    in
    let rename_blake2b = function
      | n1 :: n2 :: n3 :: n4 :: n5 :: n6 :: rest ->
          String.concat "" [ n1; n2; n3; n4; n5; n6 ] :: rest
      | _ -> assert false
    in
    let rename_public_key_hash = function
      | (("ed25519" | "secp256k1" | "p256") as k)
        :: n1 :: n2 :: n3 :: n4 :: n5 :: n6 :: rest ->
          k :: String.concat "" [ n1; n2; n3; n4; n5; n6 ] :: rest
      | _ -> assert false
    in
    (* /contracts/index/xx/xx/xx/xx/xx/xx/yyyyyyyyyy
       => /contracts/index/yyyyyyyyyy
    *)
    fold_flatten ctxt [ "contracts"; "index" ] 0 [] ~depth:7 ~rename:(drop 6)
    >>= fun ctxt ->
    (* *)
    (* /contracts/index/yyyyyyyyyy/delegated/xx/xx/xx/xx/xx/xx/zzzzzzzzzz
       => /contracts/index/yyyyyyyyyy/delegated/zzzzzzzzzz
    *)
    fold_flatten ctxt [ "contracts"; "index" ] 1 [ "delegated" ] ~depth:7
      ~rename:(drop 6)
    >>= fun ctxt ->
    (* *)
    (* /big_maps/index/xx/xx/xx/xx/xx/xx/n
       => /big_maps/index/n
    *)
    fold_flatten ctxt [ "big_maps"; "index" ] 0 [] ~depth:7 ~rename:(drop 6)
    >>= fun ctxt ->
    (* *)
    (* /big_maps/index/n/contents/yy/yy/yy/yy/yy/yyyyyyyy
       => /big_maps/index/n/contents/yyyyyyyyyyyyyyyyyy
    *)
    fold_flatten ctxt [ "big_maps"; "index" ] 1 [ "contents" ] ~depth:6
      ~rename:rename_blake2b
    >>= fun ctxt ->
    (* *)
    (* /rolls/index/x/y/n
       => /rolls/index/n
    *)
    fold_flatten ctxt [ "rolls"; "index" ] 0 [] ~depth:3 ~rename:(drop 2)
    >>= fun ctxt ->
    (* *)
    (* /rolls/owner/current/x/y/n
       => /rolls/owner/current/n
    *)
    fold_flatten ctxt
      [ "rolls"; "owner"; "current" ]
      0 [] ~depth:3 ~rename:(drop 2)
    >>= fun ctxt ->
    (* *)
    (* /rolls/owner/snapshot/n1/n2/x/y/n3
       => /rolls/owner/snapshot/n1/n2/n3
    *)
    fold_flatten ctxt
      [ "rolls"; "owner"; "snapshot" ]
      2 [] ~depth:3 ~rename:(drop 2)
    >>= fun ctxt ->
    (* *)
    (* /commitments/xx/xx/xx/xx/xx/xxxxxx
       => /commitments/xxxxxxxxxxxxxxxx
    *)
    fold_flatten ctxt [ "commitments" ] 0 [] ~depth:6 ~rename:rename_blake2b
    >>= fun ctxt ->
    (* *)
    (* /votes/listings/kk/xx/xx/xx/xx/xx/xx/xxxxxxxx
       => /votes/listings/kk/xxxxxxxxxxxxxxxxxx
    *)
    fold_flatten ctxt [ "votes"; "listings" ] 0 [] ~depth:7
      ~rename:rename_public_key_hash
    >>= fun ctxt ->
    (* *)
    (* /votes/ballots/kk/xx/xx/xx/xx/xx/xx/xxxxxxxx
       => /votes/ballots/KK/xxxxxxxxxxxxxxxxxxxx
    *)
    fold_flatten ctxt [ "votes"; "ballots" ] 0 [] ~depth:7
      ~rename:rename_public_key_hash
    >>= fun ctxt ->
    (* *)
    (* /votes/proposals_count/kk/xx/xx/xx/xx/xx/xx/xxxxxxxx
       => /votes/proposals_count/kk/xxxxxxxxxxxxxxxxxxxx
    *)
    fold_flatten ctxt
      [ "votes"; "proposals_count" ]
      0 [] ~depth:7 ~rename:rename_public_key_hash
    >>= fun ctxt ->
    (* *)
    (* /votes/proposals/xx/xx/xx/xx/xx/xx/xxxxxxxx
       => /votes/proposals/xxxxxxxxxxxxxxxxxxxx
    *)
    fold_flatten ctxt [ "votes"; "proposals" ] 0 [] ~depth:6
      ~rename:rename_blake2b
    >>= fun ctxt ->
    (* *)
    (* /votes/proposals/yyyyyyyyyyyyyyyyyyyy/kk/xx/xx/xx/xx/xx/xx/xxxxxxxx
       => /votes/proposals/yyyyyyyyyyyyyyyyyyyy/KK/xxxxxxxxxxxxxxxxxxxx
    *)
    fold_flatten ctxt [ "votes"; "proposals" ] 1 [] ~depth:7
      ~rename:rename_public_key_hash
    >>= fun ctxt ->
    (* *)
    (* /delegates/kk/xx/xx/xx/xx/xx/xx/xxxxxxxx
       => /delegates/KK/xxxxxxxxxxxxxxxxxxxx
    *)
    fold_flatten ctxt [ "delegates" ] 0 [] ~depth:7
      ~rename:rename_public_key_hash
    >>= fun ctxt ->
    (* *)
    (* /active_delegates_with_rolls/kk/xx/xx/xx/xx/xx/xx/xxxxxxxx
       => /active_delegates_with_rolls/KK/xxxxxxxxxxxxxxxxxxxx
    *)
    fold_flatten ctxt
      [ "active_delegates_with_rolls" ]
      0 [] ~depth:7 ~rename:rename_public_key_hash
    >>= fun ctxt ->
    (* *)
    (* /delegates_with_frozen_balance/n/kk/xx/xx/xx/xx/xx/xx/xxxxxxxx
       => /delegates_with_frozen_balance/n/KK/xxxxxxxxxxxxxxxxxxxx
    *)
    fold_flatten ctxt
      [ "delegates_with_frozen_balance" ]
      1 [] ~depth:7 ~rename:rename_public_key_hash
    >|= fun _ctxt ->
    [%logs.info "context storage flattening completed"];
    ()
end
