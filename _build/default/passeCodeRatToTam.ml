(* Module de typage des identifiants *)

(* doit être conforme à l'interface Passe *)
open Tds
open Ast
open Type
open Tam 
open Code

type t1 = AstPlacement.programme
type t2 = string

let rec list_concat l = 
  match l with 
  | [] -> ""
  | t::q -> (t^"\n")^(list_concat q)
  
  (*analyse_code_affectable : AstPlacement.affectable -> string
     paramètre a : affectable à analyser
     génère le code pour un affectable
     Nous avons la même fonction en dessous avec un affectable de type AstType affectable car sinon cela rentrait en conflit. C'est le seul moyen que nous avons trouvé pour résoudre le problème*)
  let analyse_code_affectable a =
    let rec aux a = 
      (match a with 
      | AstPlacement.Valeur aff -> let (str, t) = aux aff in
        (match t with 
        | Pointeur t2 -> (str^(loadi 1), t2)
        | _ -> failwith "Erreur interne")
      | AstPlacement.Ident i -> begin 
        match info_ast_to_info i with
        | InfoVar (_,Pointeur t,depl,reg)->  ((load 1 depl reg), t) 
        | _ -> failwith "Erreur interne" 
      end)
      in
    begin
    match a with
    | AstPlacement.Valeur a -> let(str, t) = aux a in
    str^(storei (getTaille t))
    | AstPlacement.Ident info ->
      begin
        match info_ast_to_info info with
      | InfoVar(_, t, dep, reg) -> store (getTaille t) dep reg
      | _ -> failwith "Probleme analyse code affectable"
      end
    end
    
  let analyse_code_affectableType a =
    let rec aux a = 
      (match a with 
      | AstType.Valeur aff -> let (str, t) = aux aff in
        (match t with 
        | Pointeur t2 -> (str^(loadi 1), t2)
        | _ -> failwith "Erreur interne")
      | AstType.Ident i -> begin 
        match info_ast_to_info i with
        | InfoVar (_,Pointeur t,depl,reg)->  ((load 1 depl reg), t) 
        | _ -> failwith "Erreur interne" 
      end)
      in
      match a with
      | AstType.Valeur a -> let(str, t) = aux a in
      str^(loadi (getTaille t))
      | AstType.Ident info ->
        begin
          match info_ast_to_info info with
          | InfoVar(_, t, dep, reg) -> load (getTaille t) dep reg
          | InfoConst(_,i) -> loadl_int i
          | _ -> failwith "Probleme analyse code affectable" 
        end

(* analyse_code_expression : AstPlacement.expression -> string *)
(* Paramètre e : l'expression à analyser *)
(* Code associé aux expressions *)
(* Erreur si mauvaise utilisation des identifiants *)
let rec analyse_code_expression e = 
  match e with
  | AstType.AppelFonction (info, le) ->
    let c = String.concat "" (List.map analyse_code_expression le) in
    (match (info_ast_to_info info) with 
    | InfoFun(f,_,_) -> 
      c ^ (call "ST" f)
    | _ -> failwith "analyse_code_expression : AppelFonction")
  | AstType.Ident info ->
    begin
    match info_ast_to_info info with
    | InfoVar(_,t,dep,reg) ->
      load (getTaille t) dep reg
    | InfoConst (_,const) -> loadl_int const
    | _ -> failwith "analyse_code_expression : Ident"
    end
  | AstType.Entier i -> loadl_int i
  | AstType.Booleen b -> if b then loadl_int 1 else loadl_int 0
  | AstType.Unaire (op,e) -> 
    let c = analyse_code_expression e in 
    begin
    match op with
    | Numerateur -> c ^ (pop (0) 1)
    | Denominateur -> c ^ (pop (1) 1)
    end
  | AstType.Binaire (op,e1,e2) ->
    let c1 = analyse_code_expression e1 in
    let c2 = analyse_code_expression e2 in
    begin
    match op with
    | PlusInt -> c1 ^ c2 ^ subr "IAdd"
    | PlusRat -> c1 ^ c2 ^ call "ST" "RAdd"
    | MultInt -> c1 ^ c2 ^ subr "IMul"
    | MultRat -> c1 ^ c2 ^ call "ST" "RMul"
    | Fraction -> c1 ^ c2 ^ call "ST" "norm"
    | EquInt -> c1 ^ c2 ^ subr "IEq"
    | EquBool -> c1 ^ c2 ^ subr "IEq"
    | Inf -> c1 ^ c2 ^ subr "ILss"
    end
  | AstType.Null -> loadl_int 0
  | AstType.New t -> (loadl_int (getTaille t))^subr "MAlloc"
  | AstType.Affectable a -> analyse_code_affectableType a
  | AstType.Adresse info ->
    begin
      match info_ast_to_info info with
      | InfoVar(_,_,dep,reg) -> loada dep reg
      | _ -> failwith "Erreur dans AstType.Adresse dans analyse code expression"
    end 
  | AstType.Ternaire(e1, e2, e3) ->
    let c1 = analyse_code_expression e1 in
    let c2 = analyse_code_expression e2 in
    let c3 = analyse_code_expression e3 in
    let iff = getEtiquette () in
    let fi = getEtiquette () in
    c1
    ^ jumpif 0 iff
    ^ c2
    ^ jump fi
    ^ label iff
    ^ c3
    ^label fi
    

(* analyse_code_instruction : AstPlacement.instruction -> string *)
(* Paramètre i : l'instruction à analyser *)
(* Code associé aux instructions *)
let rec analyse_code_instruction i =
  match i with
  | AstPlacement.Declaration (info, e) ->
    begin
      match info_ast_to_info info with 
        | InfoVar (_, t, dep, reg) -> 
          push (getTaille t)
          ^ analyse_code_expression e
         ^ store (getTaille t) dep reg
        | _ -> failwith "analyse_code_instruction : Declaration"
    end
  | AstPlacement.Affectation (a, e) ->
    let na = analyse_code_affectable a in
    let ne = analyse_code_expression e in 
    ne^na


  | AstPlacement.Conditionnelle (c, b1, b2) -> 
    let nc = analyse_code_expression c in
    let iff = getEtiquette () in
    let fi = getEtiquette () in
    nc
    ^ jumpif 0 iff
    ^ analyse_code_bloc b1
    ^ jump fi
    ^ label iff
    ^ analyse_code_bloc b2
    ^ label fi
  | AstPlacement.ConditionnelleOptionnelle (c,b) ->
    let nc = analyse_code_expression c in
    let fic = getEtiquette () in
    nc
    ^jumpif 0 fic
    ^ analyse_code_bloc b
    ^ label fic
  
  | AstPlacement.TantQue (c, b) -> 
    let nc = analyse_code_expression c in
    let wh = getEtiquette() in
    let endwhile = getEtiquette() in
    let nb = analyse_code_bloc b in
    label wh
    ^ nc
    ^ jumpif 0 endwhile
    ^ nb
    ^ jump wh
    ^ label endwhile
  | AstPlacement.AffichageInt e ->
    analyse_code_expression e
    ^ subr (label "IOUT")
  | AstPlacement.AffichageRat e ->
    analyse_code_expression e
    ^ call "ST" "ROUT"
  | AstPlacement.AffichageBool e ->
    analyse_code_expression e
    ^ subr (label "BOUT")
  | AstPlacement.AffichagePoint e ->
    analyse_code_expression e
    ^ subr (label "IOUT")
  | AstPlacement.Retour (e, tr, tp) ->
    analyse_code_expression e
    ^ (return tr tp)
  | AstPlacement.Empty -> ""
  | AstPlacement.Loop(iaBreak,b) ->
    let lp = getEtiquette() in
    let endlp = getEtiquette() in
    let nb = analyse_code_bloc b in
    modifier_string_break lp endlp iaBreak; (*Modifie les étiquettes dans l'infoLoop iaBreak pour qu'elles puisse être utilisé ultérieurement lors de la rencontre d'un continue ou d'un break. Cette fonction se trouve dans tds.mli*)
    label lp
    ^ nb
    ^ jump lp
    ^ label endlp
  | AstPlacement.Break(ia) ->
    (match info_ast_to_info ia with
      | InfoLoop (_,_,endlp) -> jump endlp
      | _ -> failwith "Erreur interne break tam")
  
  | AstPlacement.Continue(ia) ->
    (match info_ast_to_info ia with
      | InfoLoop (_,lp,_) -> jump lp
      | _ -> failwith "Erreur interne break tam")

  

(* analyse_code_bloc : AstPlacement.bloc -> string *)
(* Paramètre li : le bloc à analyser *)
(* Code associé à un bloc *)
and analyse_code_bloc li =
let (l,n) = li in
let nli = List.map analyse_code_instruction l in
(list_concat nli)^(pop 0 n)

(* analyse_code_fonction : AstPlacement.fonction -> string *)
(* Paramètre : la fonction à analyser *)
(* Code associé à la fonction *)
let analyse_code_fonction (AstPlacement.Fonction(info,_,li)) =
  match info_ast_to_info info with 
  |InfoFun (n, _, _) ->
    label n^
    analyse_code_bloc li^
    halt
    | _ -> failwith "Internal Error"

(* analyser : AstCode.programme -> string *)
(* Paramètre : le programme à analyser *)
let analyser (AstPlacement.Programme (fonctions,bloc)) = 
  let fonc = List.fold_left (fun t qt -> t ^ analyse_code_fonction qt ^ "\n") "" fonctions
  and main = "LABEL main\n" ^ (analyse_code_bloc bloc) ^ "HALT\n" in
  getEntete () ^ fonc ^ main
