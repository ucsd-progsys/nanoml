
let rec assoc (d,k,l) =
  match l with
  | [] -> d
  | (s,i)::tl -> if s = k then (s, i) else assoc (d, k, tl);;

let _ =
  assoc ((-1), "willam", [("ranjit", 85); ("william", 23); ("moose", 44)]);;