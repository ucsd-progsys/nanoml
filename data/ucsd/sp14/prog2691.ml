
let rec mulByDigit i l =
  match List.rev l with
  | [] -> []
  | h::t ->
      let f a x = a + x in
      let base = 0 in
      let rec helper acc v =
        if v = 0 then acc else (helper (v mod 10)) :: (acc (v / 10)) in
      helper []
        [List.fold_left f base
           ((mulByDigit i (List.rev (List.map (fun x  -> x * 10) t))) @
              [h * i])];;