
let rec clone x n =
  let rec aux acc n =
    if n <= 0 then acc else aux (List.append [x] acc) (n - 1) in
  aux [] n;;

let padZero l1 l2 =
  let len1 = List.length l1 in
  let len2 = List.length l2 in
  if l1 < l2
  then ((List.append (clone 0 (len2 - len1)) l1), l2)
  else (l1, (List.append (clone 0 (len1 - len2) l2)));;