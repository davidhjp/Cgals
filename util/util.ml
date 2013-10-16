module L = Batteries.List
module Hashtbl = Batteries.Hashtbl
module Q = Batteries.Queue
module Enum = Batteries.Enum

open Sexplib
open Std
open Sexp
open PropositionalLogic
open TableauBuchiAutomataGeneration


exception Internal_error of string

let build_data_stmt asignals index from stmt = 
  Systemj.backend := from; 
  let stmt = Systemj.get_data_stmt index asignals
    (match stmt with DataUpdate x -> x 
    | _ as s -> 
      output_hum stdout (sexp_of_proposition s);
      raise (Internal_error "^^^^^^^^^^^^^^^ is not a data-type statment")) in
  match from with
  | "promela" -> "c_code {\n" ^ stmt ^ "};\n"
  | _ -> stmt

let build_data_expr from index asignals expr =
  Systemj.backend := from; 
  let expr = Systemj.get_data_expr index asignals expr in
  match from with
  | "promela" -> "c_expr{" ^ expr ^ "}"
  | _ -> expr

let rec label from tf internal_signals channels index updates isignals asignals = function
  | And (x,y) -> 
    let lv = (label from tf internal_signals channels index updates isignals asignals x)  in
    let rv = (label from tf internal_signals channels index updates isignals asignals y) in
    let () = IFDEF DEBUG THEN output_hum stdout (sexp_of_list sexp_of_string [lv;rv]) ELSE () ENDIF in
    (match (lv,rv) with
    | ("false",_) | (_,"false") -> "false"
    | ("true","true") -> "true"
    | ("true",(_ as s)) | ((_ as s),"true") -> s
    | (_,_) -> "(" ^ lv ^ ")&&(" ^ rv ^ ")")
  | Or (x,y) -> 
    let lv = (label from tf internal_signals channels index updates isignals asignals x)  in
    let rv = (label from tf internal_signals channels index updates isignals asignals y) in
    (match (lv,rv) with
    | ("true",_) | (_,"true") -> "true"
    | ("false","false") -> "false"
    | ("false",(_ as s)) | ((_ as s),"false") -> s
    | (_,_) -> "(" ^ lv ^ ")||(" ^ rv ^ ")")
  | Not (Proposition x) as s-> 
    let v = (match x with 
      | Expr x ->
	  if (not (L.exists (fun t -> t = x) isignals)) then
	    if x.[0] = '$' then 
	      let () = output_hum stdout (sexp_of_logic s) in
	      raise (Internal_error "^^^^^^^^^^^^ Not emit proposition impossible!")
	    else 
	      if not (L.exists (fun t -> t = x) channels) then ("CD"^(string_of_int index)^"_"^x) 
	      else "(" ^ x ^ ")"
	  else "false"
      | DataExpr x -> build_data_expr from index asignals x
      | DataUpdate x -> raise (Internal_error ("Tried to update data " ^ (to_string_hum (Systemj.sexp_of_dataStmt x)) ^ " on a guard!!"))
      | Update x -> raise (Internal_error ("Tried to update " ^ x ^ " on a guard!!"))
      | Label x -> raise (Internal_error ("Tried to put label " ^ x ^ " on a guard!!"))) in 
    (match v with
    | "false" -> "true"
    | "true" -> "false"
    | _ -> "!("^v^")")
  | Proposition x -> (match x with 
    | Expr x -> 
	if (not (L.exists (fun t -> t = x) isignals)) then
	  if x.[0] = '$' then "true"
	  else 
	  (* This can only ever happen here! *)
	    (* if not (List.exists (fun (Update t) -> t = x) updates) then *)
	    if not (L.exists (fun t -> t = x) channels) then ("CD"^(string_of_int index)^"_"^x) 
	    else "(" ^ x ^ ")"
	    (* else "true" *)
	else "true"
    | DataExpr x -> build_data_expr from index asignals x
    | DataUpdate x -> raise (Internal_error ("Tried to update data " ^ (to_string_hum (Systemj.sexp_of_dataStmt x)) ^ " on a guard!!"))
    | Update x -> raise (Internal_error ("Tried to update " ^ x ^ " on a guard!!"))
    | Label x -> raise (Internal_error ("Tried to put label " ^ x ^ " on a guard!!"))) 
  | True -> "true"
  | False -> "false"
  | _ as s -> 
    let () = output_hum stdout (sexp_of_logic s) in
    raise (Internal_error ("Got a non known proposition type when building transition labels" ))


let rec get_updates index = function
  | And(x,y) 
  | Or(x,y) -> (get_updates index x) @ (get_updates index y)
  | Not (Proposition x) | Proposition x as s ->
    (match x with 
    | Expr x -> 
      if x.[0] = '$' then 
	[(Hashtbl.find (L.nth !update_tuple_tbl_ll index) s)]
      else []
    | _ -> [])
  | _ -> []

let get_outgoings o = function
  | ({name=n;incoming=i},guards) ->
    try
      List.iter2 (fun x g -> 
	match Hashtbl.find_option o x with
	| Some ll -> Hashtbl.replace o x ((n,g) :: ll)
	| None -> Hashtbl.add o x [(n,g)]
      ) i guards
    with
    | _ as s -> 
      output_hum stdout (sexp_of_list sexp_of_string i);
      output_hum stdout (sexp_of_list sexp_of_logic guards);
      print_endline ("Node: " ^ n);
      raise s

let rec solve q o ret lgn = 
  if not (Q.is_empty q) then
    let element = Q.pop q in
    (* Get all the outgoing nodes from element *)
    (* add these nodes to the queue if they are not already there *)
    let oo = (match Hashtbl.find_option o element.node.name with Some x -> x | None -> []) in
    let (oo,_) = L.split oo in
    (* Check if the oo contains names that are already there in the Q *)
    let oo = L.filter (fun x -> not(Enum.exists (fun y -> y.node.name = x) (Q.enum (Q.copy q)))) oo in
    (* Check if these are not already there in ret, because that means they have been visited *)
    let oo = L.filter (fun x -> not(L.exists (fun y -> y.node.name = x) !ret)) oo in
    (* Add the remaining elements *)
    let oo = L.map (fun x -> L.find (fun y -> y.node.name = x) lgn) oo in
    (* Add to q *)
    let () = List.iter (fun x -> Q.push x q) oo in
    (* Finally add the element to the return list *)
    ret := element :: !ret;
    (* Call it recursively again *)
    solve q o ret lgn
      

(* Reachability using BF traversal *)
let reachability lgn = 
  let ret = ref [] in
  let q = Q.create () in
  let o = Hashtbl.create 1000 in
  let () = L.iter (fun x -> get_outgoings o (x.node,x.guards)) lgn in
  (* Added the starting node *)
  let () = Q.push (L.find (fun {tlabels=t} -> (match t with | Proposition (Label x) -> x = "st" | _ -> false)) lgn) q in
  let () = solve q o ret lgn in
  (* Finally the list is returned *)
  L.sort_unique compare !ret


let rec map8 f a b c d e g i j = 
  match (a,b,c,d,e,g,i,j) with
  | ((h1::t1),(h2::t2),(h3::t3),(h4::t4),(h5::t5),(h6::t6),(h7::t7),(h8::t8)) -> 
    (f h1 h2 h3 h4 h5 h6 h7 h8) :: map8 f t1 t2 t3 t4 t5 t6 t7 t8
  | ([],[],[],[],[],[],[],[]) -> []
  | _ -> failwith "Lists not of equal length"


let map2i f l1 l2 = 
  let rec ff f i (l1,l2) = 
    match (l1,l2) with
    | (h::t, h2::t2) -> f i h h2 :: ff f (i+1) (t,t2)
    | ([],[]) -> []
    | _ -> failwith "Lists not of equal length"  in
  ff f 0 (l1,l2)
