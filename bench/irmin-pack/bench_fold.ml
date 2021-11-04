open Bench_common
open Irmin.Export_for_backends

type config = { root : string; commit : string }

module Benchmark = struct
  type result = { time : float; size : int; maxrss : int }

  let get_maxrss () =
    let usage = Rusage.(get Self) in
    let ( / ) = Int64.div in
    Int64.to_int (usage.maxrss / 1024L)

  let with_timer f =
    let timer = Mtime_clock.counter () in
    let+ () = f () in
    let span = Mtime_clock.count timer in
    Mtime.Span.to_ms span

  let run config f =
    let+ time = with_timer f in
    let size = FSHelper.get_size config.root in
    let maxrss = get_maxrss () in
    { time; size; maxrss }

  let pp_results ppf result =
    Format.fprintf ppf "Total time: %f@\nSize on disk: %d M@\nMaxrss: %d M"
      result.time result.size result.maxrss
end

module Conf = struct
  let entries = 32
  let stable_hash = 256
end

module Store = struct
  open Irmin_pack.Maker_ext (Irmin_pack.Version.V1) (Conf)
  include Make (Tezos_context_hash_irmin.Encoding)
end

module Flatten = Flatten.Flatten_storage_for_H (Store)

let reset_stats () =
  Irmin_pack.Stats.reset_stats ();
  Store.Tree.reset_counters ()

let stats () =
  let ips = Irmin_pack.Stats.get () in
  Fmt.epr
    "irmin-pack stats finds= %d cache_misses= %d appended_hashes= %d \
     appended_offsets= %d inode_add = %d inode_remove = %d inode_of_seq = %d \
     inode_of_raw = %d inode_rec_add = %d inode_rec_remove = %d inode_to_binv \
     = %d inode_decode_bin = %d inode_encode_bin = %d inode_hash_of_offset = %d\n"
    ips.finds ips.cache_misses ips.appended_hashes ips.appended_offsets
    ips.inode_add ips.inode_remove ips.inode_of_seq ips.inode_of_raw
    ips.inode_rec_add ips.inode_rec_remove ips.inode_to_binv
    ips.inode_decode_bin ips.inode_encode_bin ips.inode_hash_of_offset;
  Fmt.epr "tree counters = %a\n%!" Store.Tree.dump_counters ();
  Index.Stats.reset_stats ();
  Irmin_pack.Stats.reset_stats ();
  Store.Tree.reset_counters ()

let fold config =
  let conf = Irmin_pack.config ~readonly:true ~fresh:false config.root in
  let* repo = Store.Repo.v conf in
  let* commit =
    match Repr.of_string Store.Hash.t config.commit with
    | Ok x -> Store.Commit.of_hash repo x
    | Error (`Msg m) -> Fmt.kstr Lwt.fail_with "Invalid hash %S" m
  in
  let* commit =
    match commit with
    | Some c -> Lwt.return c
    | None ->
        Fmt.kstr Lwt.fail_with "Commit %S not found in the store" config.commit
  in

  let tree = Store.Commit.tree commit in
  reset_stats ();
  let* () = Flatten.flatten_storage { repo; tree } in
  stats ();
  let+ () = Store.Repo.close repo in
  ()

let main data_dir commit =
  match (data_dir, commit) with
  | None, _ | _, None -> Fmt.failwith "expected --data-dir and --commit"
  | Some data_dir, Some commit ->
      let config = { root = data_dir; commit } in
      let results =
        Lwt_main.run (Benchmark.run config (fun () -> fold config))
      in
      Fmt.epr "%a@." Benchmark.pp_results results

open Cmdliner

let data_dir =
  let doc = Arg.info ~docv:"DATA" ~doc:"Store on disk." [ "data-dir" ] in
  Arg.(value @@ opt (some string) None doc)

let commit =
  let doc =
    Arg.info ~docv:"COMMIT" ~doc:"Commit on which we call the fold."
      [ "commit" ]
  in
  Arg.(value @@ opt (some string) None doc)

let main_term = Term.(const main $ data_dir $ commit)

let () =
  let info = Term.info "Benchmarks for folds." in
  Term.exit @@ Term.eval (main_term, info)
