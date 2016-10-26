let rec compile exp code threshold = match exp with
    Lambda.Int v -> (Instruct.Const v)::code
  | Lambda.Bool v -> (Instruct.Bool v)::code
  | Lambda.Tuple (tag, vs) ->
    let n = (List.length vs) in
    if n = 0 then Instruct.MakeTuple (tag, 0)::code else
      let fn a b = compile b (Instruct.Push::a) threshold in
      let init = compile (List.hd vs) ((Instruct.MakeTuple (tag,n))::code) threshold in
      List.fold_left fn init (List.tl vs)
  | Lambda.Var n ->
    if n < threshold
    then (Instruct.StackAccess n)::code
    else (Instruct.EnvAccess (n-threshold))::code
  | Lambda.Bind t -> compile t (Instruct.Bind::code) threshold
  | Lambda.Fun (n,ts) -> (Instruct.Closure (compile_tail exp n))::code
  | Lambda.Fun1 (n,ts) -> (Instruct.Closure (compile_tail exp n))::code
    (* let body = [Instruct.Grab n] @ (compile_body ts n) in *)
    (*     (Instruct.Closure body)::code *)
  | Lambda.App (t,ts) ->
    let init = compile t [Instruct.Apply] threshold in
    let f = (fun a b -> compile b (Instruct.Push::a) threshold) in
    (Instruct.PushRetAddr code)::(List.fold_left f init ts)
  | Lambda.If (t, succ, fail) ->
    compile t [Instruct.Branch ((compile succ code threshold), (compile fail code threshold))] threshold
  | Lambda.Switch (t, cases) ->
    compile t [Instruct.Switch
                 (List.map (fun (i, x) -> (i, (compile x code threshold))) cases)] threshold
  | Lambda.Prim s -> (Instruct.Prim s)::code
  | Lambda.Plus (a, b) ->
    compile a (Instruct.Push::(compile b (Instruct.Plus::code)) threshold) threshold
  | Lambda.Sub (a, b) ->
    compile a (Instruct.Push::(compile b (Instruct.Sub::code)) threshold) threshold
  | Lambda.Mul (a, b) ->
    compile a (Instruct.Push::(compile b (Instruct.Mul::code)) threshold) threshold
  | Lambda.Div (a, b) ->
    compile a (Instruct.Push::(compile b (Instruct.Div::code)) threshold) threshold
  | Lambda.Field (n, b) ->
    compile b ((Instruct.Field n)::code) threshold
  | Lambda.Equal (a, b) ->
    compile a (Instruct.Push::(compile b (Instruct.Equal::code) threshold)) threshold
and compile_tail exp threshold = match exp with
    Lambda.Int v -> [Instruct.Const v]
  | Lambda.Bool v -> [Instruct.Bool v]
  | Lambda.Prim s -> [Instruct.Prim s]
  | Lambda.Var n -> if n < threshold
    then [Instruct.StackAccess n]
    else [Instruct.EnvAccess (n-threshold)]
  | Lambda.Bind t -> [Instruct.Bind]
  | Lambda.Switch _ -> compile exp [] threshold
  | Lambda.Tuple _ -> compile exp [] threshold
  | Lambda.Plus _ -> compile exp [] threshold
  | Lambda.Sub _ -> compile exp [] threshold
  | Lambda.Mul _ -> compile exp [] threshold
  | Lambda.Div _ -> compile exp [] threshold
  | Lambda.Equal _ -> compile exp [] threshold
  | Lambda.Field _ -> compile exp [] threshold
  | Lambda.If _ -> compile exp [] threshold
  | Lambda.Fun (n,ts) ->
    [Instruct.Grab n] @ (compile_body ts n) @ [Instruct.Return]
  | Lambda.Fun1 (n,ts) ->
    [Instruct.Grab (n-1); Instruct.Push] @ (compile_body ts n) @ [Instruct.Return]
  (* | [t] -> (match n with *)
  (*     | 0 -> compile_tail t n *)
  (*     | _ -> (Instruct.Grab n)::(compile_tail (Lambda.Fun (n-1,[t])) n)) *)
  (* | _ -> failwith "must be one") *)
  | Lambda.App (t,ts) ->
    (t::ts
     |> List.rev
     |> List.map (fun x -> compile x [] threshold)
     |> List.flatten) @ [Instruct.Apply]
and compile_body ts threshold = match ts with
  | [x] -> compile x [] threshold
  | x::xs -> compile x (compile_body xs threshold) threshold
  | [] -> []
