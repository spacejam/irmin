(*
 * Copyright (c) 2013-2014 Thomas Gazagnaire <thomas@gazagnaire.org>
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

open Ir_merge.OP

module Log = Log.Make(struct let section = "CONTENTS" end)

module type S = sig
  include Tc.S0
  val merge: t Ir_merge.t
end

module type STORE = sig
  include Ir_ao.STORE
  val merge: t -> key Ir_merge.t
  module Key: Ir_hash.S with type t = key
  module Val: S with type t = value
end

module Json = struct

  module V = struct

    type t = Ezjsonm.value

    let hash = Hashtbl.hash
    let compare = Pervasives.compare
    let equal = (=)

    let to_json x = x
    let of_json x = x

    let to_string t = Ezjsonm.(to_string (wrap t))
    let of_string s = Ezjsonm.(unwrap (from_string s))

    let write t buf =
      let str = to_string t in
      let len = String.length str in
      Cstruct.blit_from_string str 0 buf 0 len;
      Cstruct.shift buf len

    let read buf =
      Mstruct.get_string buf (Mstruct.length buf)
      |> of_string

    let size_of t =
      let str = to_string t in
      String.length str

  end

  module T = struct

    type t = Ezjsonm.t

    let hash = Hashtbl.hash
    let compare = Pervasives.compare
    let equal = (=)

    let to_json = Ezjsonm.value
    let of_json = function
      | #Ezjsonm.t as x -> x
      | j -> Ezjsonm.parse_error j "Not a valid JSON document"

    let to_string t = Ezjsonm.(to_string t)
    let of_string s = Ezjsonm.(from_string s)

    let write t buf =
      let str = to_string t in
      let len = String.length str in
      Cstruct.blit_from_string str 0 buf 0 len;
      Cstruct.shift buf len

    let read buf =
      Mstruct.get_string buf (Mstruct.length buf)
      |> of_string

    let size_of t =
      let str = to_string t in
      String.length str

  end

  include T

  let rec merge_values ~old x y =
    match old, x, y with
    | `O old, `O x, `O y ->
      Ir_merge.alist (module Tc.String) (module V) merge_values ~old:old x y >>| fun x ->
      ok (`O x)
    | _ -> conflict "JSON values"

  let merge ~old x y =
    match old, x, y with
    | `O old, `O x, `O y ->
      Ir_merge.alist (module Tc.String) (module V) merge_values ~old:old x y >>| fun x ->
      ok (`O x)
    | _ -> conflict "JSON documents"


end

module String = struct
  include Tc.String
  let size_of t = String.length t
  let read buf = Mstruct.to_string buf
  let write t buf =
    let len = String.length t in
    Cstruct.blit_from_string t 0 buf 0 len;
    Cstruct.shift buf len
  let merge = Ir_merge.default (module Tc.String)
end

module Cstruct = struct
  module S = struct
    type t = Cstruct.t

    let hash = Hashtbl.hash
    let equal x y = Cstruct.to_bigarray x = Cstruct.to_bigarray y
    let compare x y =
      Pervasives.compare (Cstruct.to_bigarray x) (Cstruct.to_bigarray y)

    let to_json t = Cstruct.to_string t |> Ezjsonm.encode_string
    let of_json j = Cstruct.of_string (Ezjsonm.decode_string_exn j)
    let size_of t = Cstruct.len t
    let read b = Mstruct.to_cstruct b

    let write t buf =
      let len = Cstruct.len t in
      Cstruct.blit t 0 buf 0 len;
      Cstruct.shift buf len
  end
  include S
  let merge = Ir_merge.default (module S)
end

module Make
    (S: sig
       include Ir_ao.STORE
       module Key: Ir_hash.S with type t = key
       module Val: S with type t = value
     end) =
struct
  include S
  let merge t = Ir_merge.biject' (module Key) Val.merge (read_exn t) (add t)
end
