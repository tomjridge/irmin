(*
 * Copyright (c) 2018-2022 Tarides <contact@tarides.com>
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
module Int63 = Optint.Int63
module Io = Irmin_pack_unix.Io.Unix
module Errs = Irmin_pack_unix.Io_errors.Make (Io)
module Mapping_file = Irmin_pack_unix.Mapping_file.Make (Errs)

let test_dir = Filename.concat "_build" "test-pack-mapping"
let mapping_path = Irmin_pack.Layout.V3.mapping ~generation:0 ~root:test_dir

(* The following routine writes the pairs to disk using Mapping_file.create; this has a
   side effect that the pairs are processed to remove dups and combine adjacent entries
   (subject to gap_tolerance); we then open the result file and return the pairs *)
(** Call the [Mapping_file] routines to process [pairs] *)
let process_on_disk pairs =
  let register_entries ~register_entry =
    List.iter
      (fun (off, len) -> register_entry ~off:(Int63.of_int off) ~len)
      pairs
  in
  let () =
    Mapping_file.create ~root:test_dir ~generation:0 ~register_entries
    |> Errs.raise_if_error
  in
  let io = Io.open_ ~path:mapping_path ~readonly:true |> Errs.raise_if_error in
  let l = ref [] in
  let f ~off ~len = l := (Int63.to_int off, len) :: !l in
  Mapping_file.iter io f |> Errs.raise_if_error;
  Io.close io |> ignore;
  !l |> List.rev

(** Emulate the behaviour of the [Mapping_file] routines to process [pairs] *)
let process_in_mem pairs =
  let length_per_offset =
    let tbl = Hashtbl.create 0 in
    List.iter
      (fun (off, len) ->
        let len =
          match Hashtbl.find_opt tbl off with
          | Some len' when len' > len -> len'
          | _ -> len
        in
        Hashtbl.replace tbl off len)
      pairs;
    tbl
  in
  (* [List.map] gets the offsets, [List.sort_uniq] sort/dedups them and
     [List.fold_left] merges the contiguous ones. *)
  List.map fst pairs
  |> List.sort_uniq compare
  |> List.fold_left
       (fun acc off ->
         let len = Hashtbl.find length_per_offset off in
         match acc with
         | [] -> [ (off, len) ]
         | (off', len') :: _ when off' + len' > off -> assert false
         | (off', len') :: tl when off' + len' = off -> (off', len' + len) :: tl
         | acc -> (off, len) :: acc)
       []
  |> List.rev
(* NOTE the "merging of the contiguous ones" doesn't take gap tolerance into account *)

(** [test input_entries] uses [process_on_disk] and [process_in_mem] to compute the result
    of "mapping file construction", which includes sorting, combining adjacent regions
    etc. The on-disk and in-mem results are compared to check they are equal. *)
let test input_entries =
  let output_entries = process_on_disk input_entries in
  let input_entries' = process_in_mem input_entries in
  Alcotest.(check (list (pair int int)))
    "Comparison between Mapping_file result and the in-memory equivalent"
    input_entries' output_entries

(* FIXME why "suffix segmentation"? this produces an array of [(off0,len0),(off1,len1)...]
   where off0=0, and off1=len0 etc. (ie the next off-len starts where the previous finishes) *)
(** Produce an array of contiguous offset/length pairs starting from offset 0 *)
let produce_suffix_segmentation len seed =
  let rng = Random.State.make [| seed |] in
  let _, elts =
    List.init len Fun.id
    |> List.fold_left
         (fun (totlen, l) _ ->
           let len = Random.State.int rng 10 + 1 in
           (totlen + len, (totlen, len) :: l))
         (0, [])
  in
  List.to_seq elts |> Array.of_seq

(* Given a "suffix segmentation" as above, produce another array consisting of the entries
   (not in order!) for some subset of array indices of the original; some entries may be
   repeated (ie an index may be chosen multiple times); some lengths may be randomized *)
(** Randomly produce a subset of the [full_seg] segmentation. *)
let produce_suffix_segmentation_subset full_seg ~seed ~max_len =
  let rng = Random.State.make [| seed |] in
  let len = Random.State.int rng max_len |> max 1 |> min max_len in
  List.init len (fun _ ->
      let i = Random.State.int rng (Array.length full_seg) in
      let off, len = full_seg.(i) in      
      if Random.State.bool rng then (off, len) (* include directly *)
      else
        let len = Random.State.int rng len |> max 1 in (* chose a random length *)
        (off, len))

let test ~full_seg_length ~seg_subset_max_length ~random_test_count =
  (* [mkdir] may fail if the directory exists. The files in it will be
     overwritten at computation time. *)
  Io.mkdir test_dir |> ignore;

  let seg = produce_suffix_segmentation full_seg_length 42 in
  (* repeatedly run produce_suffix_segmentation_subset in a loop, and pass results to
     [test] *)
  let rec aux i =
    if i >= random_test_count then ()
    else (
      produce_suffix_segmentation_subset seg ~seed:i
        ~max_len:seg_subset_max_length
      |> test; (* call the previous test function *)
      aux (i + 1))
  in
  aux 0;
  Lwt.return_unit
(* FIXME why Lwt? *)

let tests =
  [
    Alcotest_lwt.test_case "test mapping on small inputs" `Quick
      (fun _switch () ->
        test ~full_seg_length:10 ~seg_subset_max_length:30
          ~random_test_count:1000);
    Alcotest_lwt.test_case "test mapping on large inputs" `Quick
      (fun _switch () ->
        test ~full_seg_length:10000 ~seg_subset_max_length:30000
          ~random_test_count:100);
  ]
