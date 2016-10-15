let rec subst t0 v t =
  match t0 with
  | Type.Unit -> Type.Unit
  | Type.Int -> Type.Int
  | Type.Bool -> Type.Bool
  | Type.Var s -> if s = v then t else t0
  | Type.Tuple td ->
    let tuple = (List.map (fun (i,x) -> (i, (subst x v t))) td.tuple) in
    td.tuple <- tuple;
    t0
  | Type.Fun (arg,ret) ->
    Type.Fun (subst arg v t, subst ret v t)

let rec update_type t subst =
  match t with
  | Type.Unit -> Type.Unit
  | Type.Int -> Type.Int
  | Type.Bool -> Type.Bool
  | Type.Fun (arg,ret) ->
    Type.Fun (update_type arg subst, update_type ret subst)
  | Type.Tuple td ->
    let tuple = (List.map (fun (i,x) -> (i, (update_type x subst))) td.tuple) in
    td.tuple <- tuple;
    t
  | Type.Var v -> try List.assoc v subst with _ -> t

let extend_subst s v t =
  (v,t)::(List.map (fun (v1,rhs) -> (v1, (subst rhs v t))) s)

let rec occur v t =
  match t with
  | Type.Var v1 -> v = v1
  | Type.Fun (arg,ret) ->
    (occur v arg) || (occur v ret)
  | Type.Tuple td ->
    List.exists (occur v) (List.map (fun (i,v) -> v) td.tuple)
  | _ -> false

(* 'a M -> ('a -> 'b M) -> 'b M *)
let (>>=) aM a2bM = match aM with
  | None -> None
  | Some a -> a2bM a

let rec list_equal l1 l2 =
  match l1 with
  | [] -> (List.length l2) = 0
  | x::xs -> (List.mem x l2) && list_equal xs (List.filter (fun v -> v <> x) l2)

let rec list_intersection l1 l2 =
  match l1 with
  | [] -> []
  | (i,x)::xs ->
    try let y = List.assq i l2 in
      (i,x,y) :: (list_intersection xs l2) with
      _ -> list_intersection xs l2

let rec list_union l1 l2 =
  match l1 with
  | [] -> l2
  | (i,x)::xs -> if List.mem_assq i l2
    then list_union xs l2
    else (i,x)::(list_union xs l2)

let rec list_sub l1 l2 res =
  match l1 with
  | [] -> res
  | (i, x)::xs -> if List.mem_assq i l2
    then list_sub xs l2 res
    else list_sub xs l2 ((i,x)::res)

let tag_equal x y =
  match (x, y) with
  | (Type.TAny, _) -> true
  | (_, Type.TAny) -> true
  | (Type.TNone, Type.TNone) -> true
  | (Type.TExact a, Type.TExact b) -> a=b
  | (Type.TExact a, Type.TOneof l) -> List.mem a l
  | (Type.TOneof l, Type.TExact a) -> List.mem a l
  | (Type.TOneof l1, Type.TOneof l2) -> list_equal l1 l2
  | _ -> false

let is_some = function Some _ -> true | _ -> false

(* (unifier t1 t2) : ('a -> 'b M) *)
let rec unifier t1 t2 s =
  let ty1 = update_type t1 s in
  let ty2 = update_type t2 s in
  match (ty1,ty2) with
  | (Type.Int,Type.Int) -> Some s
  | (Type.Bool,Type.Bool) -> Some s
  | (Type.Unit,Type.Unit) -> Some s
  | (Type.Var a, Type.Var b) when a=b -> Some s
  | (Type.Var a, _) -> if (occur a ty2) then None
    else Some (extend_subst s a ty2)
  | (_, Type.Var b) -> if (occur b ty1) then None
    else Some (extend_subst s b ty1)
  | (Type.Fun(a1,e1), Type.Fun(a2,e2)) ->
    (Some s)
    >>= (unifier a1 a2)
    >>= (unifier e1 e2)
  | (Type.Tuple td1, Type.Tuple td2) when tag_equal td1.tag td2.tag ->
    let common = list_intersection td1.tuple td2.tuple in
    let ls1 = List.map (function (i,x,y) -> x) common in
    let ls2 = List.map (function (i,x,y) -> y) common in
    let subst1 =  unifier_list ls1 ls2 s in
    if is_some subst1 then
      (td1.tuple <- (td1.tuple @ (list_sub td2.tuple td1.tuple []));
       td2.tuple <- (td2.tuple @ (list_sub td1.tuple td2.tuple []));
       subst1)
    else None
  | _ -> None
and unifier_list t1s t2s s =
    match (t1s,t2s) with
    | ([],[]) -> Some s
    | (x::xs, y::ys) -> (unifier x y s) >>= (unifier_list xs ys)
    | _ -> None

let env_lookup env n = List.assoc n env

let env_extend env n v = (n,v)::env

let (gen_var, reset_var) = let id = ref 96 in
  (fun () -> id := !id + 1; Type.Var (Char.chr !id)),
  (fun () -> id := 96)

let make_type_tuple i n t =
  let rec recur i cur n t l =
    if cur = n then l else
    if cur = i then recur i (cur+1) n t (t::l)
    else recur i (cur+1) n t ((gen_var ())::l)
  in List.rev (recur i 0 n t [])

let rec type_of exp env subst =
  match exp with
  | Ast.Bool _ -> (Type.Bool, subst, env)
  | Ast.Int n -> (Type.Int, subst, env)
  | Ast.Equal (a,b) ->
    let (ta, subst1, env) = (type_of a env subst) in
    let subst2 = (subst1 >>= (unifier ta Type.Int)) in
    let (tb, subst3, env) = (type_of b env subst2) in
    let subst4 = (subst3 >>= (unifier tb Type.Int)) in
    (Type.Bool, subst4, env)
  | Ast.Bind (k,v) ->
    let (t, subst1, env) = type_of v env subst in
    (Type.Unit, subst1, env_extend env k t)
  | Ast.Plus (a,b) ->
    let (ta, subst1, env) = (type_of a env subst) in
    let subst2 = subst1 >>= (unifier ta Type.Int) in
    let (tb, subst3, env) = (type_of b env subst2) in
    let subst4 = subst3 >>= (unifier tb Type.Int) in
    (Type.Int, subst4, env)
  | Ast.Sub (a,b) ->
    let (ta, subst1, env) = (type_of a env subst) in
    let subst2 = subst1 >>= (unifier ta Type.Int) in
    let (tb, subst3, env) = (type_of b env subst2) in
    let subst4 = subst3 >>= (unifier tb Type.Int) in
    (Type.Int, subst4, env)
  | Ast.Mul (a,b) ->
    let (ta, subst1, env) = (type_of a env subst) in
    let subst2 = subst1 >>= (unifier ta Type.Int) in
    let (tb, subst3, env) = (type_of b env subst2) in
    let subst4 = subst3 >>= (unifier tb Type.Int) in
    (Type.Int, subst4, env)
  | Ast.Field (i,e) ->
    let result_type = gen_var () in
    let (te, subst1, env) = (type_of e env subst) in
    let should_be = Type.Tuple (Type.make_tuple_desc Type.TAny [(i, result_type)]) in
    let subst2 = (subst1 >>= (unifier te should_be)) in
    (result_type, subst2, env)
  | Ast.If (a,b,c) ->
    let (ta, subst1, env) = type_of a env subst in
    let subst2 = subst1 >>= (unifier ta Type.Bool) in
    let (tb, subst3, env) = type_of b env subst2 in
    let (tc, subst4, env) = type_of c env subst3 in
    let subst5 = subst4 >>= (unifier tb tc) in
    (tb, subst5, env)
  | Ast.Var n -> ((env_lookup env n), subst, env)
  | Ast.Fun (vars,body) -> (match vars with
      | [] -> failwith "fuck..1"
      | x::[] -> let tv = gen_var () in
        let (ty, subst1, env) = type_of_body body (env_extend env x tv) subst in
        (Type.Fun (tv, ty), subst1, env)
      | x::xs -> let tv = gen_var () in
        let (ty, subst1, env) = type_of (Ast.Fun (xs, body)) (env_extend env x tv) subst in
        (Type.Fun (tv, ty), subst1, env))
  | Ast.Tuple (name, vs) ->
    let ts = List.mapi (fun i v -> let (t, s, e) = (type_of v env subst) in (i, t)) vs in
    let tag = match name with Some str -> Global.name2tag str | None -> 0 in
    let td = Type.make_tuple_desc (Type.TExact tag) ts in
    (Type.Tuple td, subst, env)
  | Ast.Switch (v, cases) ->
    let ret = gen_var () in
    let tags = List.map (function (x,_) -> Global.name2tag x) cases in
    let ty = (Type.Tuple (Type.make_tuple_desc (Type.TOneof tags) [])) in
    let (t, subst1, e) = (type_of v env subst) in
    let subst2 = (subst1 >>= (unifier t ty)) in
    let es = List.map (function (_,y) -> y) cases in
    let subst3 = (List.fold_left (fun s e ->
        let (t,s1,env1) = (type_of e env s) in
        s1 >>= unifier t ret) subst2 es) in
    (ret, subst3, env)
  | Ast.Fun1 (vars, body) ->
    let (t, subst1, env) = type_of (Ast.Fun (vars, body)) env subst in
    (match t with
     | Type.Fun (self, _) -> (self, subst1, env)
     | _ -> failwith "Ast.fun1 fail")
  | Ast.App (rator,rands) -> type_of_app rator (List.rev rands) env subst
and type_of_body ls env subst =
  match ls with
  | [] -> failwith "fuck you"
  | x::[] -> type_of x env subst
  | x::xs ->
    let (tx, subst1, env) = (type_of x env subst) in
    let subst2 = subst1 >>= unifier tx Type.Unit in
    type_of_body xs env subst2
and type_of_app rator rev_rands env subst =
  (match rev_rands with
   | [] -> failwith "should never run here"
   | x::[] ->
     let result_type = gen_var () in
     let (rator_type, subst1, env) = type_of rator env subst in
     let (rand_type, subst2, env) = type_of x env subst1 in
     let subst3 = subst2 >>= (unifier rator_type (Type.Fun (rand_type, result_type))) in
     (result_type, subst3, env)
   | x::xs ->
     let result_type = gen_var () in
     let (rator_type, subst1, env) = type_of_app rator xs env subst in
     let (rand_type, subst2, env) = type_of x env subst1 in
     let subst3 = subst2 >>= (unifier rator_type (Type.Fun (rand_type, result_type))) in
     (result_type, subst3, env))

let infer exp =
  let () = reset_var () in
  let (ty, subst, env) = type_of exp [] (Some []) in
  match subst with
  | Some s -> update_type ty s
  | None -> failwith "false"

let infer_list es =
  let rec aux_infer es env subst =
    match es with
    | [] -> failwith "should not here"
    | x::[] -> let (ty, subst, env) = type_of x env subst in
      (match subst with
       | Some s -> (update_type ty s), env
       | None -> failwith "false")
    | x::xs -> let (ty, subst, env) = type_of x env subst in
      (match subst with
       | Some s -> aux_infer xs env subst
       | None -> failwith "false") in
  let (t, env) = aux_infer es [] (Some []) in
  t
