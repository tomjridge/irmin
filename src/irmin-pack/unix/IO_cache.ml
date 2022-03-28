let src = Logs.Src.create "irmin.pack.unix.io_cache" ~doc:"IO for irmin-pack.unix IO_cache"

module Log = (val Logs.src_log src : Logs.LOG)

module Private = struct

  (** A memoized constructor of type [('a,'v) t]: the instances created are of type ['v];
      the extra constructor arguments (beyond [fresh] and [readonly] and the anonymous
      [string] argument) are of type ['a]; the anonymous string argument is the "root"
      within which the files belonging to the cached instance will be placed *)
  type ('a, 'v) t = { v : 'a -> ?fresh:bool -> ?readonly:bool -> string -> 'v }

  (** [memoize ~v ~clear ~valid file] returns a memoized constructor using [v] as the bare
      constructor; [file : root:string -> string] is a function that takes a file name
      (i.e. a short name with no filename separators) and returns the full path by
      prepending [root]; the anonymous string argument in the resulting memoized
      constructor is then the [root] argument that is used when calling the bare
      constructor via [file] *)
  let memoize ~v ~clear ~valid (file: root:string -> string) : _ t =
    (* hashtbl keyed by [(file,readonly,pid)]; value is cached instance *)
    let files = Hashtbl.create 13 in
    let cached_constructor extra_args ?(fresh = false) ?(readonly = false) root
      =
      (* NOTE we use the [pid] for caching, because we want any subprocess -- in
         particular, the layers worker process -- to avoid any cached instances in the
         parent *)
      let pid = Unix.getpid () in
      (* file will be placed under [root] *)
      let file = file ~root in
      (* disallow [fresh && readonly]; FIXME unclear why we do this here if it is not
         enforced by the bare constructor *)
      if fresh && readonly then invalid_arg "Read-only IO cannot be fresh";
      try
        if not (Sys.file_exists file) then (
          [%log.debug
            "[%s] does not exist anymore, cleaning up the fd cache"
              (Filename.basename file)];
          (* FIXME what scenario can cause the underlying file to be removed? are we sure
             the relevant file descriptors have been closed? if not, shouldn't we do
             something about that here? *)
          (* remove cached instances of form (file,_,pid) *)
          Hashtbl.filter_map_inplace 
            (fun (file',_ro,pid') v -> if (pid',file') = (pid,file) then None else Some v)
            files;
          raise Not_found);
        let t = Hashtbl.find files (file, readonly, pid) in
        if valid t then (
          [%log.debug "found in cache: %s (readonly=%b)" file readonly];
          if fresh then clear t;
          t)
        else (
          Hashtbl.remove files (file, readonly,pid);
          raise Not_found)
      with Not_found ->
        [%log.debug
          "[%s] v fresh=%b readonly=%b" (Filename.basename file) fresh readonly];
        let t = v extra_args ~fresh ~readonly file in
        if fresh then clear t;
        Hashtbl.add files (file, readonly, pid) t;
        t
    in
    { v = cached_constructor }

end

include (Private : Irmin_pack.IO_intf.IO_cache)
