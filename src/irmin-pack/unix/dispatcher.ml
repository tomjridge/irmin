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

open Import
include Dispatcher_intf
module Payload = Control_file.Latest_payload
module Intmap = Map.Make (Int63)

(* The following [with module Io = Io.Unix] forces unix *)
module Make (Fm : File_manager.S with module Io = Io.Unix) :
  S with module Fm = Fm = struct
  module Fm = Fm
  module Io = Fm.Io
  module Suffix = Fm.Suffix
  module Mapping_file = Mapping_file.Make (Fm.Errs)
  module Errs = Fm.Errs
  module Control = Fm.Control

  let read_suffix = ref 0
  let read_prefix = ref 0
  (*TODO move them in stats*)

(*
  type mapping_value = { poff : int63; len : int }
  (** [poff] is a prefix offset (i.e. an offset in the prefix file), [len] is
      the length of the chunk starting at [poff]. *)
*)

  type mapping = Mapping of int array array (* mapping_value Intmap.t *)
  (** [mapping] is a 2-dimensional array (for efficiency.. we don't want to store pairs in
      each array slot because this introduces extra memory overhead). The first coordinate
      is the index. The second coordinate maps as follows:

      - 0 is the virtual offset that we want to translate into an offset in the prefix
      - 1 is the prefix offset
      - 2 is the length
  *)

  module Mapping_util = struct
          
    type entry = { off:int63; poff:int63; len:int }
    (** [entry] is a type for the return value from {!find_nearest_leq} *)

    (** [nearest_leq ~arr ~get ~lo ~hi ~key] returns the nearest entry in the sorted [arr]
        that is [<=] the given key. Routine is based on binary search. *)
    let nearest_leq ~arr ~get ~lo ~hi ~key = 
      assert(lo<=hi);
      match get arr lo <= key with
      | false -> 
        (* trivial case: arr[lo] > key; so all arr entries greater than key, since arr is
           sorted *)
        `All_gt_key
      | true -> 
        (* NOTE arr[lo] <= key *)
        (* trivial case: arr[hi] <= key; then within the range lo,hi the nearest leq entry
           is at index hi *)
        match get arr hi <= key with
        | true -> `Some hi
        | false -> 
          (* NOTE key < arr[hi] *)
          (lo,hi) |> iter_k (fun ~k:kont (lo,hi) -> 
              (* loop invariants *)
              assert(get arr lo <= key && key < get arr hi);
              assert(lo < hi); (* follows from arr[lo] <= key < arr[hi] *)
              match lo+1 = hi with 
              | true -> `Some lo
              | false -> 
                (* NOTE at least one entry between arr[lo] and arr[hi] *)
                assert(lo+2 <= hi);
                let mid = (lo+hi)/2 in
                let arr_mid = get arr mid in
                match arr_mid <= key with 
                | true -> kont (mid,hi)
                | false -> 
                  (* NOTE we can't call kont with mid-1 because we need the loop invariant
                     (key < arr[hi]) to hold *)
                  kont (lo,mid))

    (* FIXME move to test directory *)
    let _test_nearest_leq () = 
      let arr = Array.of_list [1;3;5;7] in
      let get arr i = arr.(i) in
      let lo,hi = 0,Array.length arr -1 in
      let nearest_leq_ key = nearest_leq ~arr ~get ~lo ~hi ~key in
      assert(nearest_leq_ 0 = `All_gt_key); 
      assert(nearest_leq_ 1 = `Some 0);
      assert(nearest_leq_ 2 = `Some 0);
      assert(nearest_leq_ 3 = `Some 1);
      assert(nearest_leq_ 3 = `Some 1);
      assert(nearest_leq_ 4 = `Some 1);
      assert(nearest_leq_ 5 = `Some 2);
      assert(nearest_leq_ 6 = `Some 2);
      assert(nearest_leq_ 7 = `Some 3);
      assert(nearest_leq_ 8 = `Some 3);
      assert(nearest_leq_ 100 = `Some 3);
      ()

    (** [find_nearest_leq ~mapping off] returns the entry in [mapping] whose offset is the
        nearest [<=] the given [off] *)
    let find_nearest_leq ~(mapping:mapping) off =
      match mapping with 
      | Mapping arr -> 
        match Array.length arr with
        | 0 -> 
          (* NOTE this is probably an error case; perhaps log an error *)
          ignore(Stdlib.exit (-1));
          None
        | len -> 
          let get arr i = arr.(i).(0) in
          match nearest_leq ~arr ~get ~lo:0 ~hi:(len-1) ~key:(Int63.to_int off) with
          | `All_gt_key -> None
          | `Some i -> 
            let off, poff, len = arr.(i).(0), arr.(i).(1), arr.(i).(2) in
            Some { off=Int63.of_int off; poff=Int63.of_int poff; len }
          
  end

  type t = { fm : Fm.t; mutable mapping : mapping; root : string }
  (** [mapping] is a map from global offset to (offset,len) pairs in the prefix
      file *)

  let empty_mapping = Mapping (Array.make_matrix 0 3 0)

  let load_mapping path =
    let arr = Mapping_file.load_mapping_as_mmap path in
    (* NOTE arr is an array of pairs (off,len); so the size needs to be adjusted by /2 in
       the following line *)
    let mapping = Array.make_matrix ((BigArr1.dim arr) / 2) 3 0 in
    let poff = ref 0 in
    let idx = ref 0 in
    let f ~off ~len =
      let off = Int63.to_int off in
      (* We want to map off to poff,len *)
      mapping.(!idx).(0) <- off;
      mapping.(!idx).(1) <- !poff;
      mapping.(!idx).(2) <- len;
      poff := !poff + len;
      incr idx;
      ()
    in
    Mapping_file.iter_mmap arr f;
    Ok (Mapping mapping)


  let reload t =
    let open Result_syntax in
    let* mapping =
      match Fm.mapping t.fm with
      | None -> Ok empty_mapping (* presumably not used *)
      | Some path -> load_mapping path
    in
    t.mapping <- mapping;
    Ok ()

  let v ~root fm =
    let open Result_syntax in
    let t = { fm; mapping = empty_mapping; root } in
    Fm.register_mapping_consumer fm ~after_reload:(fun () -> reload t);
    let* () = reload t in
    Ok t

  let entry_offset_suffix_start t =
    let pl = Control.payload (Fm.control t.fm) in
    match pl.status with
    | Payload.From_v1_v2_post_upgrade _
    | From_v3_used_non_minimal_indexing_strategy | From_v3_no_gc_yet ->
        Int63.zero
    | T1 | T2 | T3 | T4 | T5 | T6 | T7 | T8 | T9 | T10 | T11 | T12 | T13 | T14
    | T15 ->
        assert false
    | From_v3_gced { entry_offset_suffix_start; _ } -> entry_offset_suffix_start

  (* The suffix only know the real offsets, it is in the dispatcher that global
     offsets are translated into real ones (i.e. in prefix or suffix offsets). *)
  let end_offset t =
    let open Int63.Syntax in
    Suffix.end_offset (Fm.suffix t.fm) + entry_offset_suffix_start t

  (* Adjust the read in suffix, as the global offset [off] is
     [off] = [entry_offset_suffix_start] + [suffix_offset]. *)
  let suffix_off_of_offset t off =
    let open Int63.Syntax in
    let entry_offset_suffix_start = entry_offset_suffix_start t in
    off - entry_offset_suffix_start

  let offset_of_suffix_off t suffix_off =
    let open Int63.Syntax in
    let entry_offset_suffix_start = entry_offset_suffix_start t in
    suffix_off + entry_offset_suffix_start

  (* Find the last chunk which is before [off_start] (or at [off_start]). If no
     chunk found, then the entry was possibly gced (case 1). If [off_start] is
     after the entry's chunk then the entry was possibly gced (case 2). Note
     that for these two cases we cannot distinguished between trying to read a
     gced entry, or doing an invalid read. We expose two [read_exn] functions
     and we handled this upstream. *)
  let chunk_of_off_exn mapping off_start =
    (* NOTE off_start is a virtual offset *)
    let open Int63 in
    let open Int63.Syntax in
    let res = Mapping_util.find_nearest_leq ~mapping off_start in
    match res with
    | None ->
        (* Case 1: The entry if before the very first chunk (or there are no
           chunks). Possibly the entry was gced. *)
        let s =
          Fmt.str "offset %a is before the first chunk, or the prefix is empty"
            Int63.pp off_start
        in
        raise (Errors.Pack_error (`Invalid_read_of_gced_object s))
    | Some (entry: Mapping_util.entry) ->
      let chunk_off_start = entry.off in
        assert (chunk_off_start <= off_start);
        let chunk_len = entry.len in
        let chunk_off_end = chunk_off_start + of_int chunk_len in

        (* Case 2: The entry starts after the chunk. Possibly the entry was
           gced. *)
        (if chunk_off_end <= off_start then
         let s =
           Fmt.str
             "offset %a is supposed to be contained in chunk \
              (off=%a,poff=%a,len=%d) but starts after chunk"
             Int63.pp off_start Int63.pp chunk_off_start Int63.pp entry.poff
             entry.len
         in
         raise (Errors.Pack_error (`Invalid_read_of_gced_object s)));

        let shift_in_chunk = off_start - chunk_off_start in
        let max_entry_len = of_int chunk_len - shift_in_chunk in

        (entry, shift_in_chunk, max_entry_len)

  (* After we find the chunk of an entry, we check that a read is possible in the
     chunk. If it's not, this is always an invalid read. *)
  let poff_of_entry_exn mapping ~off ~len =
    let chunk, shift_in_chunk, max_entry_len = chunk_of_off_exn mapping off in

    (* Case 3: The entry ends after the chunk *)
    let open Int63 in
    let open Int63.Syntax in
    (if of_int len > max_entry_len then
     let s =
       Fmt.str
         "entry (off=%a, len=%d) is supposed to be contained in chunk \
          (poff=%a,len=%d) and starting at %a but is larger than it can be\n\
         \ contained in chunk" Int63.pp off len Int63.pp chunk.poff chunk.len
         Int63.pp shift_in_chunk
     in
     raise (Errors.Pack_error (`Invalid_prefix_read s)));

    (* Case 4: Success *)
    chunk.poff + shift_in_chunk

  let get_prefix fm =
    match Fm.prefix fm with
    | Some prefix -> prefix
    | None -> raise (Errors.Pack_error (`Invalid_prefix_read "no prefix found"))

  let read_exn t ~off ~len buf =
    let open Int63.Syntax in
    let entry_offset_suffix_start = entry_offset_suffix_start t in
    if off >= entry_offset_suffix_start then (
      incr read_suffix;
      let suffix_off = suffix_off_of_offset t off in
      try Suffix.read_exn (Fm.suffix t.fm) ~off:suffix_off ~len buf
      with e ->
        let to_int = Int63.to_int in
        Fmt.epr "\n%!";
        Fmt.epr "exception!\n%!";
        Fmt.epr "%#d %#d %#d %#d\n%!" (to_int off) len
          (to_int entry_offset_suffix_start)
          (to_int @@ end_offset t);
        Fmt.epr "\n%!";
        raise e)
    else (
      incr read_prefix;
      let poff = poff_of_entry_exn t.mapping ~off ~len in
      let prefix = get_prefix t.fm in
      Io.read_exn prefix ~off:poff ~len buf;
      ())

  let read_in_prefix_and_suffix_exn t ~off ~len buf =
    let ( -- ) a b = a - b in
    let open Int63.Syntax in
    let entry_offset_suffix_start = entry_offset_suffix_start t in
    if
      off < entry_offset_suffix_start
      && off + Int63.of_int len > entry_offset_suffix_start
    then (
      let read_in_prefix = entry_offset_suffix_start - off |> Int63.to_int in
      read_exn t ~off ~len:read_in_prefix buf;
      let read_in_suffix = len -- read_in_prefix in
      let buf_suffix = Bytes.create read_in_suffix in
      read_exn t ~off:entry_offset_suffix_start ~len:read_in_suffix buf_suffix;
      Bytes.blit buf_suffix 0 buf read_in_prefix read_in_suffix)
    else read_exn t ~off ~len buf

  let read_if_not_gced t ~off ~len buf =
    try
      read_exn t ~off ~len buf;
      true
    with Errors.Pack_error (`Invalid_read_of_gced_object _) -> false

  let read_at_most_from_suffix_exn t ~off ~len buf =
    let bytes_after_off = Int63.sub (end_offset t) off in
    let len =
      let open Int63.Syntax in
      if bytes_after_off < Int63.of_int len then Int63.to_int bytes_after_off
      else len
    in
    let suffix_off = suffix_off_of_offset t off in
    Suffix.read_exn (Fm.suffix t.fm) ~off:suffix_off ~len buf;
    len

  let read_at_most_from_prefix_exn t ~off ~len buf =
    let chunk, shift_in_chunk, max_entry_len = chunk_of_off_exn t.mapping off in
    let fm = t.fm in
    let open Int63 in
    let open Int63.Syntax in
    let min a b = if a < b then a else b in
    let len = min max_entry_len (of_int len) |> to_int in
    let poff = chunk.poff + shift_in_chunk in
    let prefix = get_prefix fm in
    Io.read_exn prefix ~off:poff ~len buf;
    len

  let read_at_most_exn t ~off ~len buf =
    let open Int63.Syntax in
    let entry_offset_suffix_start = entry_offset_suffix_start t in
    if off >= entry_offset_suffix_start then
      read_at_most_from_suffix_exn t ~off ~len buf
    else read_at_most_from_prefix_exn t ~off ~len buf
end
