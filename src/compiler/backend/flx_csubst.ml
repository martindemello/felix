open Flx_types
open Flx_typing
open List
open Flx_util
open Flx_exceptions
open Flx_ctypes
open Flx_cexpr

(* substitution encoding:
   $n: n'th component of argument tuple, 1 origin!
   $a: expands to $1, $2, .. $n
   $b: expands to $2, .. $n
   `n: n'th component of argument tuple, reference kind

   #x: expands to #x for all 'x' other than those below

   #n: type of n'th component of argument tuple (1 origin)
   #0: return type
   @n: reference to shape object

   $t: pass a tuple argument 'as a tuple'
   $Tn: pass argument n expanded into an argument list (varargs)
   #t: the type of the argument tuple
   @t: the shape of the argument tuple
   @dn: expands to first n components of display, excluding thread frame

   ??: expands to ?
   ?n: the n'th generic type argument ..
   @?n: the n'th generic type argument shape ..
   ?a: expands to ?1,?2, ...

*)

(* finite state machine states *)
type mode_t =
  | Normal
  | CString
  | CChar
  | CStringBackslash
  | CCharBackslash
  | Dollar
  | Backquote
  | Hash
  | Earhole
  | Quest
  | DollarDigits
  | BackquoteDigits
  | HashDigits
  | EarholeDigits
  | EarholeDisplayDigits
  | EarholeQuestDigits
  | QuestDigits
  | Varargs
  | VarargsDigits
  | DollarDigitsPrec
  | Escape

let pr = function
  | Normal -> "Normal"
  | CString -> "CString"
  | CChar -> "CChar"
  | CStringBackslash -> "CStringBackslash"
  | CCharBackslash -> "CCharBackslash"
  | Dollar -> "Dollar"
  | Backquote -> "Backquote"
  | Hash -> "Hash"
  | Earhole -> "Earhole"
  | Quest -> "Quest"
  | DollarDigits -> "DollarDigits"
  | BackquoteDigits -> "BackquoteDigits"
  | HashDigits -> "HashDigits"
  | EarholeDigits -> "EarholeDigits"
  | EarholeDisplayDigits -> "EarholeDisplayDigits"
  | EarholeQuestDigits -> "EarholeQuestDigits"
  | QuestDigits -> "QuestDigits"
  | Varargs -> "Varargs"
  | VarargsDigits -> "VarargsDigits"
  | DollarDigitsPrec -> "DollarDigitsPrec"
  | Escape -> "Escape"

let is_idletter ch =
  ch >= '0' && ch <='9' ||
  ch >= 'A' && ch <='Z' ||
  ch >= 'a' && ch <='z' ||
  ch = '_'

(* identifier or integer *)
let is_atomic s =
  try
    for i = 0 to String.length s - 1 do
      if not (is_idletter s.[i]) then raise Not_found
    done;
    true
  with Not_found -> false

let islower = function | 'a' .. 'z' -> true | _ -> false

let csubst sr sr2 ct arg (args:cexpr_t list) typs argtyp retyp gargs prec argshape argshapes display gargshapes =
  (*
  print_endline ("INPUT ct,prec=" ^ ct ^ " is " ^ prec);
  *)
  let ct,prec = Flx_cexpr.genprec ct prec in
  (*
  print_endline ("OUTPUT ct,prec=" ^ ct ^ " is " ^ prec);
  *)
  let n = length args in
  assert (n = length typs);
  (* print_endline ("CSUBST " ^ ct ^ ", count="^si n^", result prec=" ^ prec); *)
  let len = String.length ct in
  let buf = Buffer.create (n * 2 + 20) in
  let bcat s = Buffer.add_string buf s in
  let chcat c = Buffer.add_char buf c in
  let mode = ref Normal in
  let precname = ref "" in
  let digits = ref 0 in
  let serr i msg =
    let spc k = String.make k ' ' in
    clierr2 sr sr2
    (
      "[csubst] " ^ msg ^ " in code fragment \n\"" ^ ct ^
       "\"\n" ^ spc (i+1) ^ "^" ^ "\n" ^ "Column " ^ string_of_int (i+1)
    )
  in
  let rec trans i ch =
    match !mode with
    | Normal ->
      begin match ch with
      | '$' -> mode := Dollar
      | '`' -> mode := Backquote
      | '#' -> mode := Hash
      | '@' -> mode := Earhole
      | '?' -> mode := Quest
      | '\\' -> mode := Escape
      | '"' -> chcat ch; mode := CString
      | '\'' -> chcat ch; mode := CChar
      | _ -> chcat ch
      end

    | Escape ->
      chcat ch; mode := Normal

    | CString ->
      begin match ch with
      | '"' -> chcat ch; mode := Normal
      | '\\' -> chcat ch; mode := CStringBackslash
      | _ -> chcat ch
      end

    | CChar ->
      begin match ch with
      | '\'' -> chcat ch; mode := Normal
      | '\\' -> chcat ch; mode := CCharBackslash
      | _ -> chcat ch
      end

    | CStringBackslash ->
      chcat ch;
      mode := CString

    | CCharBackslash ->
      chcat ch;
      mode := CChar

    | Dollar ->
      begin match ch with
      | 'a' ->
        bcat (catmap ", " string_of_cexpr args);
        mode := Normal

      | 'b' ->
        bcat (catmap ", " string_of_cexpr (List.tl args));
        mode := Normal

      | 't' ->
        bcat (string_of_cexpr arg);
        (*
        bcat ( argtyp ^ "(" ^ catmap "," string_of_cexpr args ^ ")");
        *)
        mode := Normal

      | 'T' ->
        mode := Varargs

      | '0' .. '9' ->
        digits := Char.code ch - Char.code '0';
        mode := DollarDigits

      | _ -> serr i "Expected 't' or digit after $"
      end

    | Varargs ->
      begin match ch with
      | '0' .. '9' ->
        digits := Char.code ch - Char.code '0';
        mode := VarargsDigits

      | _ -> serr i "Expected digits after $T"
      end

    | Backquote ->
      begin match ch with
      | '0' .. '9' ->
        digits := Char.code ch - Char.code '0';
        mode := BackquoteDigits

      | _ -> serr i "Expected digit after `"
      end

    | Quest ->
      begin match ch with
      | '?' ->
        chcat '?';
        mode := Normal

      | '0' .. '9' ->
        digits := Char.code ch - Char.code '0';
        mode := QuestDigits

      | 'a' ->
        bcat ( cat "," gargs);
        mode := Normal

      | _ -> serr i "Expected '?a' or digit after ?"
      end

    | Earhole ->
      begin match ch with
      | 't' ->
        bcat ( argshape );
        mode := Normal

      | 'd' ->
        digits := 0;
        mode := EarholeDisplayDigits

     | '?' ->
        digits := 0;
        mode := EarholeQuestDigits

      | '0' .. '9' ->
        digits := Char.code ch - Char.code '0';
        mode := EarholeDigits

      | _ -> serr i "Expected 't' or digit after @"
      end

    | EarholeDisplayDigits ->
      begin match ch with
      | '0' .. '9' ->
        digits := Char.code ch - Char.code '0'

      | _ ->
        let d = String.concat "," (list_prefix display !digits) in
        bcat d;
        mode := Normal;
        trans i ch
      end

    | EarholeQuestDigits ->
      begin match ch with
      | '0' .. '9' ->
        digits := Char.code ch - Char.code '0'

      | _ ->
        if !digits> List.length gargs
        then serr i ("Generic type parameter ?" ^ string_of_int !digits ^ " too large")
        else if !digits<1 then serr i ("Generic type arg no " ^ string_of_int !digits ^ " too small")
        else
          bcat
          (
            nth gargshapes (!digits-1)
          );
        mode := Normal;
        trans i ch
      end

    | Hash ->
      begin match ch with
      | 't' ->
        bcat argtyp;
        mode := Normal

      | '0' .. '9' ->
        digits := Char.code ch - Char.code '0';
        mode := HashDigits

      | x -> chcat '#'; chcat x; mode:= Normal
      end

    | DollarDigits ->
      begin match ch with
      | '0' .. '9' ->
        digits := !digits * 10 + Char.code ch - Char.code '0'

      | ':' when i+1<len && islower (ct.[i+1]) ->
        precname := "";
        mode := DollarDigitsPrec

      | _ ->
        if !digits> List.length args
        then serr i
          ("Parameter $" ^ string_of_int !digits ^ " > number of arguments, only got " ^ si (length args))
        else if !digits<=0 then serr i ("Negative $" ^ string_of_int !digits)
        else begin
          let s' = nth args (!digits-1) in
          let s' = string_of_cexpr s' in
          if is_atomic s' then bcat s'
          else bcat ("(" ^ s' ^ ")");
          mode := Normal;
          trans i ch
        end
      end

    | DollarDigitsPrec ->
      begin match ch with
      | 'a'..'z' -> precname := !precname ^ String.make 1 ch
      | _ ->
        if !digits> List.length args
        then serr i
          ("Parameter $" ^ string_of_int !digits ^ " > number of arguments, only got " ^ si (length args))
        else if !digits<=0 then serr i ("Negative $" ^ string_of_int !digits)
        else
          let s' = nth args (!digits-1) in
          let s' =
            try sc !precname s'
            with Unknown_prec s-> clierr2 sr sr2 ("Unknown precedence " ^ s)
          in
          bcat s';
          mode := Normal;
          trans i ch
      end

    | VarargsDigits ->
      begin match ch with
      | '0' .. '9' ->
        digits := !digits * 10 + Char.code ch - Char.code '0'

      | _ ->
        if !digits> List.length args
        then serr i ("Parameter no $T" ^ string_of_int !digits ^ " too large")
        else if !digits<=0 then serr i ("Arg no " ^ string_of_int !digits ^ " too small")
        else
          let s' = nth args (!digits-1) in
          let s' = string_of_cexpr s' in
          let n = String.length s' in
          begin
            try
              let start = String.index s' '('
              and fin = String.rindex s' ')'
              in
              let s' = String.sub s' (start+1) (fin-start-1)
              in
                (* WE SHOULD CHECK THE # of args agrees with
                the type of the tuple .. but there is no
                way to do that since we only get a string
                representation .. this code is unequivocably
                a HACK
                *)
                bcat s';
                mode := Normal;
                trans i ch
            with Not_found ->
              (* serr i "Varargs requires  literal tuple" *)
              bcat s';
              mode := Normal;
              trans i ch
          end
       end

    | BackquoteDigits ->
      begin match ch with
      | '0' .. '9' ->
        digits := !digits * 10 + Char.code ch - Char.code '0'

      | _ ->
        if !digits> List.length args
        then serr i ("Parameter `" ^ string_of_int !digits ^ " too large")
        else if !digits<=0 then serr i ("Arg no " ^ string_of_int !digits ^ " too small")
        else
          let s' = nth args (!digits-1) in
          let s' = string_of_cexpr s' in
          let t' = nth typs (!digits-1) in
          bcat ("("^t'^"*)(" ^ s' ^ ".data)");
          mode := Normal;
          trans i ch
       end

    | EarholeDigits ->
        if !digits> List.length args
        then serr i ("Parameter @" ^ string_of_int !digits ^ " too large")
        else if !digits<0 then serr i ("Arg no " ^ string_of_int !digits ^ " too small")
        else
          let t = nth argshapes (!digits-1) in
          bcat (argshape);
          mode := Normal;
          trans i ch

    | HashDigits ->
        if !digits> List.length args
        then serr i ("Paramater #" ^ string_of_int !digits ^ " too large")
        else if !digits<0 then serr i ("Arg no " ^ string_of_int !digits ^ " too small")
        else
          bcat
          (
            if !digits = 0
            then retyp
            else nth typs (!digits-1)
          );
          mode := Normal;
          trans i ch

    | QuestDigits ->
        if !digits> List.length gargs
        then serr i ("Generic type parameter ?" ^ string_of_int !digits ^ " too large")
        else if !digits<1 then serr i ("Generic type arg no " ^ string_of_int !digits ^ " too small")
        else
          bcat
          (
            nth gargs (!digits-1)
          );
          mode := Normal;
          trans i ch
in
  for i = 0 to len - 1 do trans i ct.[i] done;
  begin match !mode with
  | CChar
  | Normal -> ()
  | HashDigits
  | EarholeDigits
  | DollarDigits
  | DollarDigitsPrec
  | QuestDigits
    -> trans len ' ' (* hack .. space is harmless *)
  | _ -> serr len ("Unexpected end in mode " ^ pr !mode)
  end;
  let prec = if prec = "" then "expr" else prec in
  ce prec (Buffer.contents buf)