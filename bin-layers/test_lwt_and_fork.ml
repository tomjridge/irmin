(** Simple test of semantics of lwt and fork *)

open Lwt.Infix

(*

let p = 
  Lwt.return () >>= fun () -> 
  Unix.fork () |> function
  | 0 -> begin
      (* child *)
      Lwt.return () >>= fun () -> 
      Printf.printf "hello world!\n%!";
      Lwt.return ()
    end
  | _pid -> 
    Lwt.return () >>= fun () -> 
    Printf.printf "hello world!\n%!";
    Lwt.return ()  

let _ = Lwt_main.run p

(python3_setup_venv) /tmp/l/github/irmin-worktree-layers2 $ dune exec bin-layers/test_lwt_and_fork.exe
hello world!
hello world!
*)

(*
let p = 
  Lwt.return () >>= fun () -> 
  Lwt_unix.fork () |> function
  | 0 -> begin
      (* child *)
      Lwt.return () >>= fun () -> 
      Printf.printf "hello world!\n%!";
      Lwt.return ()
    end
  | _pid -> 
    Lwt.return () >>= fun () -> 
    Printf.printf "hello world!\n%!";
    Lwt.return ()  

let _ = Lwt_main.run p

$ dune exec bin-layers/test_lwt_and_fork.exe
hello world!
hello world!
*)


let p = 
  Lwt.return () >>= fun () -> 
  Lwt_unix.fork () |> function
  | 0 -> begin
      (* child *)
      Lwt.return () >>= fun () -> 
      Printf.printf "hello world!\n%!";
      Lwt.return ()
    end
  | _pid -> 
    Lwt.return () >>= fun () -> 
    Printf.printf "hello world!\n%!";
    Lwt.return ()  

let _ = Lwt_main.run p
