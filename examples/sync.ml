open Lwt
open Irmin_unix

let () =
  try match Sys.getenv "DEBUG" with
    | "" -> ()
    | _  ->
      Log.color_on ();
      Log.set_log_level Log.DEBUG
  with Not_found -> ()

let path =
  if Array.length Sys.argv = 2 then
    Sys.argv.(1)
  else
    "git://github.com/mirage/ocaml-git.git"

module S = Irmin.Basic (Irmin_git.FS) (Irmin.Contents.String)

module Sync = Irmin.Sync(S)

let upstream =
  (* Note: https:// and http:// are not yet supported *)
  Irmin.remote_uri path

let test () =
  let config = Irmin_git.config ~root:"/tmp/test" () in
  S.create config task >>= fun t ->
  Sync.pull_exn (t "Syncing with upstream store") upstream `Update >>= fun () ->
  S.read_exn (t "get the README") ["README.md"]>>= fun readme ->
  Printf.printf "%s\n%!" readme;
  return_unit

let () =
  Lwt_main.run (test ())
