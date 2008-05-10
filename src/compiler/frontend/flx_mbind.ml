open Flx_util
open Flx_ast
open Flx_types
open Flx_print
open Flx_typing
open Flx_lookup
open Flx_srcref
open Flx_typing
open Flx_exceptions
open List

type extract_t =
  | Proj_n of range_srcref * int             (* tuple projections 1 .. n *)
  | Udtor of range_srcref * qualified_name_t (* argument of union component s *)
  | Proj_s of range_srcref * string          (* record projection name *)

(* the extractor is a function to be applied to
   the argument to extract the value of the identifier;
   it is represented here as a list of functions
   to be applied, with the function at the top
   of the list to be applied last.

   Note that the difference between an abstract
   extractor and a concrete one is that the
   abstract one isn't applied to anything,
   while the concrete one is applied to a specific
   expression.
*)

let gen_extractor
  (extractor : extract_t list)
  (mv : expr_t)
: expr_t =
  List.fold_right
  (fun x marg -> match x with
    | Proj_n (sr,n) -> `AST_get_n (sr,(n,marg))
    | Udtor (sr,qn) -> `AST_ctor_arg (sr,(qn,marg))
    | Proj_s (sr,s) -> `AST_get_named_variable (sr,(s,marg))
  )
  extractor
  mv

(* this routine is used to substitute match variables
   in a when expression with their bindings ..
   it needs to be completed!!!
*)
let rec subst vars (e:expr_t) mv : expr_t =
  let subst e = subst vars e mv in
  (* FIXME: most of these cases are legal, the when clause should
     be made into a function call to an arbitrary function, passing
     the match variables as arguments.

     We can do this now, since we have type extractors matching
     the structure extractors Proj_n and Udtor (ie, we can
     name the types of the arguments now)
  *)
  match e with
  | `AST_patvar _
  | `AST_patany _
  | `AST_case _
  | `AST_vsprintf _
  | `AST_interpolate _
  | `AST_type_match _
  | `AST_noexpand _
  | `AST_letin _
  | `AST_cond _
  | `AST_expr _
  | `AST_typeof _
  | `AST_product _
  | `AST_void _
  | `AST_sum _
  | `AST_andlist _
  | `AST_orlist _
  | `AST_typed_case _
  | `AST_case_arg _
  | `AST_arrow _
  | `AST_longarrow _
  | `AST_superscript _
  | `AST_match _
  | `AST_regmatch _
  | `AST_string_regmatch _
  | `AST_reglex _
  | `AST_ellipsis _
  | `AST_parse _
  | `AST_sparse _
  | `AST_setunion _
  | `AST_setintersection _
  | `AST_intersect _
  | `AST_isin _
  | `AST_macro_ctor _
  | `AST_macro_statements  _
  | `AST_callback _
  | `AST_record_type _
  | `AST_variant_type _
  | `AST_lift  _
  | `AST_user_expr _
    ->
      let sr = src_of_expr e in
      clierr sr "[mbind:subst] Not expected in when part of pattern"

  | `AST_case_index _ -> e
  | `AST_index _  -> e
  | `AST_the _  -> e
  | `AST_lookup _ -> e
  | `AST_suffix _ -> e
  | `AST_literal _ -> e
  | `AST_case_tag _ -> e
  | `AST_as _ -> e

  | `AST_name (sr,name,idx) ->
    if idx = [] then
    if Hashtbl.mem vars name
    then
      let sr,extractor = Hashtbl.find vars name in
      gen_extractor extractor mv
    else e
    else failwith "Can't use indexed name in when clause :("



  | `AST_deref (sr,e') -> `AST_deref (sr,subst e')
  | `AST_ref (sr,e') -> `AST_ref (sr,subst e')
  | `AST_likely (sr,e') -> `AST_likely (sr,subst e')
  | `AST_unlikely (sr,e') -> `AST_unlikely (sr,subst e')
  | `AST_new (sr,e') -> `AST_new (sr,subst e')
  | `AST_lvalue (sr,e') -> `AST_lvalue (sr,subst e')
  | `AST_apply (sr,(f,e)) -> `AST_apply (sr,(subst f,subst e))
  | `AST_map (sr,f,e) -> `AST_map (sr,subst f,subst e)
  | `AST_tuple (sr,es) -> `AST_tuple (sr,map subst es)
  | `AST_record (sr,es) -> `AST_record (sr,map (fun (s,e)->s,subst e) es)
  | `AST_variant (sr,(s,e)) -> `AST_variant (sr,(s,subst e))
  | `AST_arrayof (sr,es) -> `AST_arrayof (sr,map subst es)


  (* Only one of these should occur, but I can't
     figure out which one at the moment
  *)
  | `AST_method_apply (sr,(id,e,ts)) ->
    `AST_method_apply (sr,(id, subst e,ts))

  (*
  | `AST_dot (sr,(e,id,ts)) ->
    `AST_dot (sr,(subst e, id,ts))
  *)

  | `AST_dot (sr,(e,e2)) ->
    `AST_dot (sr,(subst e, subst e2))

  | `AST_lambda _ -> assert false

  | `AST_match_case _
  | `AST_ctor_arg _
  | `AST_get_n _
  | `AST_get_named_variable _
  | `AST_get_named_method _
  | `AST_match_ctor _
    ->
    let sr = src_of_expr e in
    clierr sr "[subst] not implemented in when part of pattern"

  | `AST_coercion _ -> failwith "subst: coercion"

(* This routine runs through a pattern looking for
  pattern variables, and adds a record to a hashtable
  keyed by each variable name. The data recorded
  is the list of extractors which must be applied
  to 'deconstruct' the data type to get the part
  which the variable denotes in the pattern

  for example, for the pattern

    | Ctor (1,(x,_))

  the extractor for x is

    [Udtor "Ctor"; Proj_n 2; Proj_n 1]

  since x is the first component of the second
  component of the argument of the constructor "Ctor"
*)

let rec get_pattern_vars
  vars      (* Hashtable of variable -> range_srcref * extractor *)
  pat       (* pattern *)
  extractor (* extractor for this pattern *)
=
  match pat with
  | `PAT_name (sr,id) -> Hashtbl.add vars id (sr,extractor)

  | `PAT_tuple (sr,pats) ->
    let n = ref 0 in
    List.iter
    (fun pat ->
      let sr = src_of_pat pat in
      let extractor' = (Proj_n (sr,!n)) :: extractor in
      incr n;
      get_pattern_vars vars pat extractor'
    )
    pats

  | `PAT_regexp _ ->
    failwith "[get_pattern_vars] Can't handle regexp yet"

  | `PAT_nonconst_ctor (sr,name,pat) ->
    let extractor' = (Udtor (sr, name)) :: extractor in
    get_pattern_vars vars pat extractor'

  | `PAT_as (sr,pat,id) ->
    Hashtbl.add vars id (sr,extractor);
    get_pattern_vars vars pat extractor

  | `PAT_coercion (sr,pat,_)
  | `PAT_when (sr,pat,_) ->
    get_pattern_vars vars pat extractor

  | `PAT_record (sr,rpats) ->
    List.iter
    (fun (s,pat) ->
      let sr = src_of_pat pat in
      let extractor' = (Proj_s (sr,s)) :: extractor in
      get_pattern_vars vars pat extractor'
    )
    rpats

  | _ -> ()

let rec gen_match_check pat (arg:expr_t) =
  let lint sr t i = `AST_literal (sr,`AST_int (t,i))
  and lstr sr s = `AST_literal (sr,`AST_string s)
  and lfloat sr t x = `AST_literal (sr,`AST_float (t,x))
  and apl sr f x =
    `AST_apply
    (
      sr,
      (
        `AST_name (sr,f,[]),
        x
      )
    )
  and apl2 sr f x1 x2 =
    match f,x1,x2 with
    | "land",`AST_typed_case(_,1,`TYP_unitsum 2),x -> x
    | "land",x,`AST_typed_case(_,1,`TYP_unitsum 2) -> x
    | _ ->
    `AST_apply
    (
      sr,
      (
        `AST_name (sr,f,[]),
        `AST_tuple (sr,[x1;x2])
      )
    )
  and truth sr = `AST_typed_case (sr,1,flx_bool)
  and ssrc x = short_string_of_src x
  in
  match pat with
  | `PAT_int (sr,t,i) -> apl2 sr "eq" (lint sr t i) arg
  | `PAT_string (sr,s) -> apl2 sr "eq" (lstr sr s) arg
  | `PAT_nan sr -> apl sr "isnan" arg
  | `PAT_none sr -> clierr sr "Empty pattern not allowed"

  (* ranges *)
  | `PAT_int_range (sr,t1,i1,t2,i2) ->
    let b1 = apl2 sr "le" (lint sr t1 i1) arg
    and b2 = apl2 sr "le" arg (lint sr t2 i2)
    in apl2 sr "land" b1 b2

  | `PAT_string_range (sr,s1,s2) ->
    let b1 = apl2 sr "le" (lstr sr s1) arg
    and b2 = apl2 sr "le" arg (lstr sr s2)
    in apl2 sr "land" b1 b2

  | `PAT_float_range (sr,x1,x2) ->
    begin match x1,x2 with
    | (Float_plus (t1,v1), Float_plus (t2,v2)) ->
      if t1 <> t2 then
        failwith ("Inconsistent endpoint types in " ^ ssrc sr)
      else
        let b1 = apl2 sr "le" (lfloat sr t1 v1) arg
        and b2 = apl2 sr "le" arg (lfloat sr t2 v2)
        in apl2 sr "land" b1 b2

    | (Float_minus(t1,v1), Float_minus (t2,v2)) ->
      if t1 <> t2 then
        failwith ("Inconsistent endpoint types in " ^ ssrc sr)
      else
        let b1 = apl2 sr "le" (lfloat sr t1 ("-"^ v1)) arg
        and b2 = apl2 sr "le" arg (lfloat sr t2 ("-"^v2))
        in apl2 sr "land" b1 b2


    | (Float_minus (t1,v1), Float_plus (t2,v2)) ->
      if t1 <> t2 then
        failwith ("Inconsistent endpoint types in " ^ ssrc sr)
      else
        let b1 = apl2 sr "le" (lfloat sr t1 ("-"^ v1)) arg
        and b2 = apl2 sr "le" arg (lfloat sr t2 v2)
        in apl2 sr "land" b1 b2


    | (Float_minus (t1,v1), Float_inf) ->
        apl2 sr "le" (lfloat sr t1 ("-"^ v1)) arg

    | (Float_plus (t1,v1), Float_inf) ->
        apl2 sr "le" (lfloat sr t1 v1) arg

    | (Float_minus_inf, Float_minus (t2,v2)) ->
        apl2 sr "le" arg (lfloat sr t2 ("-"^v2))

    | (Float_minus_inf, Float_plus (t2,v2)) ->
        apl2 sr "le" arg (lfloat sr t2 v2)

    | (Float_minus_inf , Float_inf ) ->
       apl sr "not" (apl sr "isnan" arg)


    | (Float_plus _, Float_minus _)
    | (Float_inf, _)
    | (_ , Float_minus_inf) ->
      failwith ("Empty float range at " ^ ssrc sr)
    end

  (* other *)
  | `PAT_name (sr,_) -> truth sr
  | `PAT_tuple (sr,pats) ->
    let counter = ref 1 in
    List.fold_left
    (fun init pat ->
      let sr = src_of_pat pat in
      let n = !counter in
      incr counter;
      apl2 sr "land" init
        (
          gen_match_check pat (`AST_get_n (sr,(n, arg)))
        )
    )
    (
      let pat = List.hd pats in
      let sr = src_of_pat pat in
      gen_match_check pat (`AST_get_n (sr,(0, arg)))
    )
    (List.tl pats)

  | `PAT_record (sr,rpats) ->
    List.fold_left
    (fun init (s,pat) ->
      let sr = src_of_pat pat in
      apl2 sr "land" init
        (
          gen_match_check pat (`AST_get_named_variable (sr,(s, arg)))
        )
    )
    (
      let s,pat = List.hd rpats in
      let sr = src_of_pat pat in
      gen_match_check pat (`AST_get_named_variable (sr,(s, arg)))
    )
    (List.tl rpats)

  | `PAT_any sr -> truth sr
  | `PAT_regexp _ ->
    failwith "[gen_match_check] Can't handle regexp yet"
  | `PAT_const_ctor (sr,name) ->
    `AST_match_ctor (sr,(name,arg))

  | `PAT_nonconst_ctor (sr,name,pat) ->
    let check_component = `AST_match_ctor (sr,(name,arg)) in
    let tuple = `AST_ctor_arg (sr,(name,arg)) in
    let check_tuple = gen_match_check pat tuple in
    apl2 sr "land" check_component check_tuple

  | `PAT_coercion (sr,pat,_)
  | `PAT_as (sr,pat,_) ->
    gen_match_check pat arg

  | `PAT_when (sr,pat,expr) ->
    let vars =  Hashtbl.create 97 in
    get_pattern_vars vars pat [];
    apl2 sr "land" (gen_match_check pat arg) (subst vars expr arg)