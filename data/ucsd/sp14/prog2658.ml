
let rec mulByDigit i l =
  match l with
  | [] -> []
  | h::t ->
      let rec helper acc v =
        if v = 0 then acc else helper ((v mod 10) :: acc) (v / 10) in
      (match (mulByDigit i (List.rev (List.map (fun x  -> x * 10) t))) @
               [helper [] (h * i)]
       with
       | [] -> []
       | h::t -> h);;