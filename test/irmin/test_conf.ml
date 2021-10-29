(*
 * Copyright (c) 2013-2021 Thomas Gazagnaire <thomas@gazagnaire.org>
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

open Irmin.Backend.Conf

let test_conf () =
  let spec_a = Spec.v "a" in
  let spec_b = Spec.v "b" in
  let x = key ~spec:spec_a "x" Irmin.Type.int 0 in
  let _y = key ~spec:spec_a "y" Irmin.Type.int 1 in
  let conf_a = add (empty spec_a) x 1 in
  let () = Alcotest.(check int) "x" 1 (get conf_a x) in
  let () =
    Alcotest.check_raises "Wrong spec"
      (Invalid_argument "invalid config key: x") (fun () ->
        ignore (add (empty spec_b) x 1))
  in
  let specs =
    Spec.list () |> Seq.map Spec.name |> List.of_seq |> List.sort String.compare
  in
  let () =
    Alcotest.(check (list string)) "Spec list" [ "a"; "b"; "mem" ] specs
  in
  let keys =
    Spec.keys spec_a
    |> Seq.map (fun (K k) -> name k)
    |> List.of_seq
    |> List.sort String.compare
  in
  let () = Alcotest.(check (list string)) "Key list" [ "x"; "y" ] keys in
  ()

let suite = [ Alcotest_lwt.test_case_sync "conf" `Quick test_conf ]
