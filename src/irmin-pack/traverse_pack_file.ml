open! Import
module IO = IO.Unix

module Stats : sig
  type t

  val empty : unit -> t
  val add : t -> Pack_value.Kind.t -> unit
  val duplicate_entry : t -> unit
  val missing_hash : t -> unit
  val pp : t Fmt.t
end = struct
  module Kind = Pack_value.Kind

  type t = {
    pack_values : int array;
    mutable duplicates : int;
    mutable missing_hashes : int;
  }

  let empty () =
    let pack_values = Array.make (List.length Kind.all) 0 in
    { pack_values; duplicates = 0; missing_hashes = 0 }

  let incr t n = t.pack_values.(n) <- t.pack_values.(n) + 1
  let add t k = incr t (Kind.to_enum k)
  let duplicate_entry t = t.duplicates <- t.duplicates + 1
  let missing_hash t = t.missing_hashes <- t.missing_hashes + 1

  let pp =
    let open Fmt.Dump in
    let pack_values =
      ListLabels.map Kind.all ~f:(fun k ->
          let name = Fmt.str "%a" Kind.pp k in
          let index = Kind.to_enum k in
          field name (fun t -> t.pack_values.(index)) Fmt.int)
    in
    record
      (pack_values
      @ [
          field "Duplicated entries" (fun t -> t.duplicates) Fmt.int;
          field "Missing entries" (fun t -> t.missing_hashes) Fmt.int;
        ])
end

module type Args = sig
  module Hash : Irmin.Hash.S
  module Index : Pack_index.S with type key := Hash.t (* presumably only needed for the index fixup code *)
  module Inode : Inode.S with type hash := Hash.t
  (* module Dict : Pack_dict.S *)
  module Contents : Pack_value.S
  module Commit : Pack_value.S
end

module Make (Args : Args) : sig
  val run :
    [ `Reconstruct_index of [ `In_place | `Output of string ]
    | `Check_index
    | `Check_and_fix_index ] ->
    Irmin.config ->
    unit
end = struct
  open Args

  let pp_key = Irmin.Type.pp Hash.t
  let decode_key = Irmin.Type.(unstage (decode_bin Hash.t))
  let decode_kind = Irmin.Type.(unstage (decode_bin Pack_value.Kind.t))

  (* [Repr] doesn't yet support buffered binary decoders, so we hack one
     together by re-interpreting [Invalid_argument _] exceptions from [Repr]
     as requests for more data. *)
  exception Not_enough_buffer

  type index_value = int63 * int * Pack_value.Kind.t
  [@@deriving irmin ~equal ~pp]

  type index_binding = { key : Hash.t; data : index_value }
  type missing_hash = { idx_pack : int; binding : index_binding }

  let pp_binding ppf x =
    let off, len, kind = x.data in
    Fmt.pf ppf "@[<v 0>%a with hash %a@,pack offset = %a, length = %d@]"
      Pack_value.Kind.pp kind pp_key x.key Int63.pp off len

  module Index_reconstructor = struct
    let create ~dest config =
      let dest =
        match dest with
        | `Output path ->
            if IO.exists path then
              Fmt.invalid_arg "Can't reconstruct index. File already exits.";
            path
        | `In_place ->
            if Conf.readonly config then raise S.RO_not_allowed;
            Conf.root config
      in
      let log_size = Conf.index_log_size config in
      [%log.app
        "Beginning index reconstruction with parameters: { log_size = %d }"
          log_size];
      let index = Index.v ~fresh:true ~readonly:false ~log_size dest in
      index

    let iter_pack_entry index key data =
      Index.add index key data;
      Ok ()

    let finalise index () =
      (* Ensure that the log file is empty, so that subsequent opens with a
         smaller [log_size] don't immediately trigger a merge operation. *)
      [%log.app "Completed indexing of pack entries. Running a final merge ..."];
      Index.try_merge index;
      Index.close index
  end

  module Index_checker = struct
    let create config =
      let log_size = Conf.index_log_size config in
      [%log.app
        "Beginning index checking with parameters: { log_size = %d }" log_size];
      let index =
        Index.v ~fresh:false ~readonly:true ~log_size (Conf.root config)
      in
      (index, ref 0)

    let iter_pack_entry (index, idx_ref) key data =
      match Index.find index key with
      | None ->
          Error (`Missing_hash { idx_pack = !idx_ref; binding = { key; data } })
      | Some data' when not @@ equal_index_value data data' ->
          Error `Inconsistent_entry
      | Some _ ->
          incr idx_ref;
          Ok ()

    let finalise (index, _) () = Index.close index
  end

  module Index_check_and_fix = struct
    let create config =
      let log_size = Conf.index_log_size config in
      [%log.app
        "Beginning index checking with parameters: { log_size = %d }" log_size];
      let root = Conf.root config in
      let index = Index.v ~fresh:false ~readonly:false ~log_size root in
      (index, ref 0)

    let iter_pack_entry (index, idx_ref) key data =
      match Index.find index key with
      | None ->
          Index.add index key data;
          Error (`Missing_hash { idx_pack = !idx_ref; binding = { key; data } })
      | Some data' when not @@ equal_index_value data data' ->
          Error `Inconsistent_entry
      | Some _ ->
          incr idx_ref;
          Ok ()

    let finalise (index, _) () =
      [%log.app "Completed indexing of pack entries. Running a final merge ..."];
      Index.try_merge index;
      Index.close index
  end

  let decode_entry_length = function
    | Pack_value.Kind.Contents -> Contents.decode_bin_length
    | Commit_v1 | Commit_v2 -> Commit.decode_bin_length
    | Inode_v1_stable | Inode_v1_unstable | Inode_v2_root | Inode_v2_nonroot ->
        Inode.decode_bin_length

  let decode_entry_exn ~off ~buffer ~buffer_off =
    try
      let pos = ref buffer_off in
      (* Decode the key and kind by hand *)
      let key = decode_key buffer pos in
      assert (!pos = buffer_off + Hash.hash_size);
      let kind = decode_kind buffer pos in
      assert (!pos = buffer_off + Hash.hash_size + 1);
      (* Get the length of the entire entry *)
      let entry_len = decode_entry_length kind buffer buffer_off in
      { key; data = (off, entry_len, kind) }
    with
    (* FIXME don't understand these - checking for exact string match??? fragile; and at
       least the "String.blit" one isn't an error msg that can occur? *)
    | Invalid_argument msg when msg = "index out of bounds" ->
        raise Not_enough_buffer
    | Invalid_argument msg when msg = "String.blit / Bytes.blit_string" ->
        raise Not_enough_buffer

  let ingest_data_file ~progress ~total pack iter_pack_entry =
    let buffer = ref (Bytes.create 1024) in
    let refill_buffer ~from =
      let read = IO.read pack ~off:from !buffer in
      let filled = read = Bytes.length !buffer in
      let eof = Int63.equal total (Int63.add from (Int63.of_int read)) in
      if (not filled) && not eof then
        Fmt.failwith
          "When refilling from offset %#Ld (total %#Ld), read %#d but expected \
           %#d"
          (Int63.to_int64 from) (Int63.to_int64 total) read
          (Bytes.length !buffer)
    in
    let expand_and_refill_buffer ~from =
      let length = Bytes.length !buffer in
      if length > 1_000_000_000 (* 1 GB *) then
        Fmt.failwith
          "Couldn't decode the value at offset %a in %d of buffer space. \
           Corrupted data file?"
          Int63.pp from length
      else (
        buffer := Bytes.create (2 * length);
        refill_buffer ~from)
    in
    let stats = Stats.empty () in
    let rec loop_entries ~buffer_off off missing_hash =
      if off >= total then (stats, missing_hash)
      else
        let buffer_off, off, missing_hash =
          match
            decode_entry_exn ~off
              ~buffer:(Bytes.unsafe_to_string !buffer)
              ~buffer_off
          with
          | { key; data } ->
              let off', entry_len, kind = data in
              let entry_lenL = Int63.of_int entry_len in
              assert (off = off');
              [%log.debug
                "k = %a (off, len, kind) = (%a, %d, %a)" pp_key key Int63.pp off
                  entry_len Pack_value.Kind.pp kind];
              Stats.add stats kind;
              let missing_hash =
                match iter_pack_entry key data with
                | Ok () -> Option.map Fun.id missing_hash
                | Error `Inconsistent_entry ->
                    Stats.duplicate_entry stats;
                    Option.map Fun.id missing_hash
                | Error (`Missing_hash x) ->
                    Stats.missing_hash stats;
                    Some x
              in
              progress entry_lenL;
              (buffer_off + entry_len, off ++ entry_lenL, missing_hash)
          | exception Not_enough_buffer ->
              let () =
                if buffer_off > 0 then
                  (* Try again with the value at the start of the buffer. *)
                  refill_buffer ~from:off
                else
                  (* The entire buffer isn't enough to hold this value: expand it. *)
                  expand_and_refill_buffer ~from:off
              in
              (0, off, missing_hash)
        in
        loop_entries ~buffer_off off missing_hash
    in
    refill_buffer ~from:Int63.zero;
    loop_entries ~buffer_off:0 Int63.zero None

  let run mode config =
    let iter_pack_entry, finalise, message =
      match mode with
      | `Reconstruct_index dest ->
          let open Index_reconstructor in
          let v = create ~dest config in
          (iter_pack_entry v, finalise v, "Reconstructing index")
      | `Check_index ->
          let open Index_checker in
          let v = create config in
          (iter_pack_entry v, finalise v, "Checking index")
      | `Check_and_fix_index ->
          let open Index_check_and_fix in
          let v = create config in
          (iter_pack_entry v, finalise v, "Checking and fixing index")
    in
    let run_duration = Mtime_clock.counter () in
    let root = Conf.root config in
    let pack_file = Filename.concat root "store.pack" in
    let pack =
      IO.v ~fresh:false ~readonly:true
        ~version:(Some Pack_store.selected_version) pack_file
    in
    let total = IO.offset pack in
    let stats, missing_hash =
      let bar =
        let open Progress.Line.Using_int63 in
        list
          [ const message; bytes; elapsed (); bar total; percentage_of total ]
      in
      Progress.(with_reporter bar) (fun progress ->
          ingest_data_file ~progress ~total pack iter_pack_entry)
    in
    finalise ();
    IO.close pack;
    let run_duration = Mtime_clock.count run_duration in
    let store_stats fmt =
      Fmt.pf fmt "Store statistics:@,  @[<v 0>%a@]" Stats.pp stats
    in
    match missing_hash with
    | None ->
        [%log.app
          "%a in %a. %t"
            Fmt.(styled `Green string)
            "Success" Mtime.Span.pp run_duration store_stats]
    | Some x ->
        let msg =
          match mode with
          | `Check_index -> "Detected missing entries"
          | `Check_and_fix_index ->
              "Detected missing entries and added them to index"
          | _ -> assert false
        in
        [%log.err
          "%a in %a.@,\
           First pack entry missing from index is the %d entry of the pack:@,\
          \  %a@,\
           %t"
            Fmt.(styled `Red string)
            msg Mtime.Span.pp run_duration x.idx_pack pp_binding x.binding
            store_stats]
end



(** Refactored version of above code, to isolate pack reading *)
module Private = struct

  (* abbrev *)
  open struct
    module P = struct
      include Printf
      let s = sprintf
    end
  end
  
  (* NOTE as before, but no index *)
  module type Args = sig
    module Hash : Irmin.Hash.S
    module Inode : Inode.S with type hash := Hash.t
    module Contents : Pack_value.S
    module Commit : Pack_value.S
  end

  module Make (Args : Args) = struct
    open Args

    let decode_key = Irmin.Type.(unstage (decode_bin Hash.t))
    let decode_kind = Irmin.Type.(unstage (decode_bin Pack_value.Kind.t))


    let decode_entry_length : Pack_value.Kind.t -> string -> int -> int = function
      | Pack_value.Kind.Contents -> Contents.decode_bin_length
      | Commit_v1 | Commit_v2 -> Commit.decode_bin_length
      | Inode_v1_stable | Inode_v1_unstable | Inode_v2_root | Inode_v2_nonroot ->
        Inode.decode_bin_length

    type entry = { off:int; len:int; key: Hash.t; kind:Pack_value.Kind.t }

    (** [decode_entry_exn ~off ~buf] returns the entry at the offset [off] in the pack
        file. [buf] is a buffer (as a string) used for decoding *)
    let decode_entry_exn ~off ~(buf:string) : [ `Ok of entry | `Error ] =
      try
        let buf_pos = ref 0 in
        (* Decode the key and kind by hand *)
        let key = decode_key buf buf_pos in
        let _ = assert (!buf_pos = Hash.hash_size) in
        let kind = decode_kind buf buf_pos in
        let _ = assert (!buf_pos = Hash.hash_size + 1) in
        (* Get the length of the entire entry *)
        let entry_len = decode_entry_length kind buf 0 in
        `Ok { key; off; len=entry_len; kind }
      with
      | Invalid_argument _ -> 
        (* [Repr] doesn't yet support buffered binary decoders, so we hack one
           together by re-interpreting [Invalid_argument _] exceptions from [Repr]
           as requests for more data. *)
        `Error

    (* NOTE the following code is rather generic: we have a pread-like file, and we want
       to read records from it, but we don't know how long each record is; so we read into
       a buffer, and keep trying to decode items from the buffer; if we fail to decode, we
       drop the prefix of the buffer we already processed, refill the buffer, and keep
       going *)

    type state = { 
      pack_size    : int; (* stop when off = pack_size  *)
      pack         : IO.t;
      mutable off  : int; (* offset within pack file *)
      mutable buf  : bytes; (* buffer for decoding *)
      mutable boff : int; (* offset within buffer *)
      mutable blen : int; (* number of bytes from boff that have been loaded from off in
                             the pack; bytes outside (boff,boff+len-1) should not be
                             accessed *)
    }

    (* if not enough data, move data from boff to begnning of buf, and read some more data
       to fill rest of buf *)
    let refill_buffer s =
      (* move (region boff blen) to start of buffer *)
      begin 
        let { buf; boff; blen; _ } = s in
        match boff = 0 with 
        | true -> ()
        | false -> 
          Bytes.blit buf boff buf 0 blen
      end;
      s.boff <- 0;
      let buf,blen = s.buf,s.blen in
      (* now fill bytes from blen *)
      let buf_suffix = Bytes.sub buf blen (Bytes.length buf - blen) in      
      let n = IO.read s.pack ~off:(s.off + blen |> Int63.of_int) buf_suffix in
      (if n <> Bytes.length buf_suffix then 
         (* expect end of file *)
         assert(s.off+blen+n=s.pack_size));
      s.blen <- s.blen + n;
      ()         

    (* process a single entry *)
    let get_entry_and_advance (s:state) =
      assert(s.off < s.pack_size);
      let decode () = 
        let buf = Bytes.sub s.buf s.boff s.blen |> Bytes.to_string in
        decode_entry_exn ~off:s.off ~buf 
      in
      let entry = 
        match decode () with
        | `Ok e -> e
        | `Error ->          
          refill_buffer s;
          match decode () with
          | `Ok e -> e
          | `Error -> 
            (* can extend buffer here, or just start with a large buffer *)
            failwith (P.s "%s: cannot read entry at offset %d with buffer of size %d"
                        __FILE__ s.off (Bytes.length s.buf))
      in
      s.off <- s.off + entry.len; (* new offset to read from *)
      (* advance boff (and adjust blen) if possible, otherwise refill *)
      (match entry.len <= s.blen with
       | true -> (s.boff <- s.boff + entry.len; s.blen <- s.blen - entry.len)
       | false -> (s.boff <- 0; s.blen <- 0; refill_buffer s));
      entry
    
    let iter_entries f pack =
      let s = { 
        pack_size=IO.size pack;
        pack;
        off=0;
        buf=Bytes.create (100*1024*1024); (* 100MB *)
        boff=0;
        blen=0;
      }
      in
      refill_buffer s;
      let rec loop () = 
        match s.off >= s.pack_size with
        | true -> ()
        | false -> 
          let entry = get_entry_and_advance s in
          f entry;
          loop ()
      in
      loop ()
  end

end (* Private *)
