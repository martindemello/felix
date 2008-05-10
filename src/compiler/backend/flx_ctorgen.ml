open Flx_util
open Flx_ast
open Flx_types
open Flx_mtypes1
open Flx_mtypes2
open Flx_print
open Flx_typing
open Flx_name
open Flx_tgen
open Flx_unify
open Flx_csubst
open Flx_exceptions
open Flx_display
open List
open Flx_generic
open Flx_label
open Flx_unravel
open Flx_ogen
open Flx_ctypes
open Flx_cexpr
open Flx_maps

let gen_ctor syms bbdfns name display funs extra_args extra_inits ts props =
  let requires_ptf = mem `Requires_ptf props in
  let requires_pc = mem `Yields props in
  name^"::"^name^
  (if length display + length extra_args = 0 then
  (if requires_ptf then "(FLX_FPAR_DECL_ONLY)" else "()")
  else
  "\n  (\n" ^
  (if requires_ptf then
  "    FLX_FPAR_DECL\n"
  else ""
  )
  ^
  cat ",\n"
  (
    map
    (
      fun (i,vslen) ->
        let instname = cpp_instance_name syms bbdfns i (list_prefix ts vslen) in
      "    " ^ instname ^ " *pptr" ^ instname
    )
    display
    @
    map
    (
      fun (t,a) -> "    " ^ t ^ " _"^a
    )
    extra_args
  )^
  "\n  )\n"
  )
  ^
  (if
    length display + length funs +
    length extra_args + length extra_inits +
    (if requires_pc then 1 else 0)
    = 0
  then (if requires_ptf then "FLX_FMEM_INIT_ONLY" else "")
  else
  (if requires_ptf then
  "  FLX_FMEM_INIT "
  else " : "
  )
  ^
  cat ",\n"
  (
    (if requires_pc then ["pc(0)"] else [])
    @
    map
    (
      fun (i,vslen) -> let instname = cpp_instance_name syms bbdfns i (list_prefix ts vslen) in
      "  ptr" ^ instname ^ "(pptr"^instname^")"
    )
    display
    @
    map
    (fun (index,t)->
      cpp_instance_name syms bbdfns index ts
      ^ "(0)"
    )
    funs
    @
    map
    (fun (t,a) -> "  " ^a ^ "(_"^a^")")
    extra_args
    @
    map
    (fun x -> "  " ^x)
    extra_inits
  )) ^
  " {}\n"