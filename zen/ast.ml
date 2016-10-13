type t =
    Int of int
  | Bool of bool
  | Var of string
  | App of t * t list
  | Fun of string list * t list
  | Fun1 of string list * t list
  | Bind of string * t
  | Tuple of t list
  | TagTuple of string * t list
  | If of t * t * t
  | Plus of t * t
  | Sub of t * t
  | Mul of t * t
  | Equal of t * t
  | Switch of t * (string * t) list
