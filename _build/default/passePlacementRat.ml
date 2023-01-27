(* Module de typage des identifiants *)
(* doit être conforme à l'interface Passe *)
open Tds
open Ast
open Type

type t1 = Ast.AstType.programme
type t2 = Ast.AstPlacement.programme

(*getTailleList : typ list -> int
   lp : liste de paramètre
   renvoie la taille d'une liste*)
let rec getTailleList lp = match lp with
| [] -> 0
| t::q -> getTaille t + getTailleList q

(*getTailleInfoList : typ list -> int
   li : liste d'info
   renvoie la taille d'une liste d'info*)
let rec getTailleInfoList li =
  match li with
  | [] -> 0
  | t::q -> 
    begin
      match t with
        | InfoVar(_,t,_,_) -> getTaille t + (getTailleInfoList q)
        | _ -> failwith "getTailleInfoList error"
    end

(*analyse_placement_affectable : AstType.affectable -> AstPlacement.affectable * typ
   a : affectable à analyser
   effectue la phase de placement d'un affectable*)
    let rec analyse_placement_affectable a =
      match a with
      | AstType.Valeur v ->
        begin
          match analyse_placement_affectable v with
          |(na, Pointeur t) -> AstPlacement.Valeur na, t
          | _ -> failwith "Ce n'est pas un pointeur"
        end
      | AstType.Ident info ->
        begin
          match info_ast_to_info info with
          | InfoVar (_,t,_,_) -> AstPlacement.Ident info, t
          | InfoConst _ -> (AstPlacement.Ident info, Int)
          | _ -> failwith "Erreur dans analyse type affectable"
        end

(* analyse_placement_expression : AstTds.expression -> AstType.expression *)
(* Paramètre e : l'expression à analyser *)
(* Effectue la phase de placement et tranforme l'expression
en une expression de type AstPlacement.expression *)
(* Erreur si mauvaise utilisation des identifiants *)
let analyse_placement_expression e = 
  e
 
(* analyse_placement_instruction : AstType.instruction -> int -> string -> AstPlacement.instruction *)
(* Paramètre i : l'instruction à analyser *)
(* Effectue la phase de placement de l'instruction *)
(* Erreur si mauvaise utilisation des identifiants *)
let rec analyse_placement_instruction i depl reg =
  match i with
  | AstType.Declaration (info, e) ->
    begin
      match info_ast_to_info info with
        | InfoVar(_ ,t ,_ ,_ ) -> modifier_adresse_variable depl reg info;
        (AstPlacement.Declaration(info, e), getTaille t)
        | _ -> failwith "Internal Error"
    end
  | AstType.Affectation (a,e) -> let (na, _) = analyse_placement_affectable a in (AstPlacement.Affectation(na, e), 0)
  | AstType.AffichageInt e -> (AstPlacement.AffichageInt e, 0)
  | AstType.AffichageRat e -> (AstPlacement.AffichageRat e, 0)
  | AstType.AffichageBool e -> (AstPlacement.AffichageBool e, 0)
  | AstType.AffichagePoint e -> (AstPlacement.AffichagePoint e, 0)
  | AstType.Conditionnelle (e,b1,b2) ->
      let nb1 = analyse_placement_bloc b1 depl reg in
      let nb2 = analyse_placement_bloc b2 depl reg in
     (AstPlacement.Conditionnelle (e, nb1, nb2), 0)
  | AstType.ConditionnelleOptionnelle (e,b) ->
    let nb = analyse_placement_bloc b depl reg in
   (AstPlacement.ConditionnelleOptionnelle (e, nb), 0)
  | AstType.TantQue (c,b) ->
      let nb = analyse_placement_bloc b depl reg in
      (AstPlacement.TantQue (c, nb),0)
  | AstType.Retour (e, info) -> 
    begin
      match info_ast_to_info info with
        | InfoFun(_ ,t ,lp ) ->
        (AstPlacement.Retour(e, getTaille t, getTailleList lp), 0)
        | _ -> failwith "Error sur le retour"
    end
  | AstType.Empty -> (AstPlacement.Empty,0)
  | AstType.Loop(iaBreak,b) -> let nb = analyse_placement_bloc b depl reg in
    (AstPlacement.Loop(iaBreak,nb),0)
  | AstType.Break(ia) -> AstPlacement.Break(ia),0
  | AstType.Continue(ia) -> AstPlacement.Continue(ia), 0
      


(* analyse_Placement_bloc : AstType.bloc -> AstPlacement.bloc *)
(* Paramètre li : liste d'instructions à analyser *)
(* Effectue le placement des élements du bloc et tranforme le bloc en un bloc de type AstPlacement.bloc *)
and analyse_placement_bloc li depl reg = 
    match li with
      | [] -> ([],0)
      | i::li -> let (ni,ti) = analyse_placement_instruction i depl reg in 
      let (ntl, tli) = analyse_placement_bloc li (depl+ti) reg  in (ni::ntl, ti+tli)

(* analyse_type_fonction : AstType.fonction -> AstPlacement.fonction *)
(* Paramètre : lsa fonction à analyser *)
(* Phase de placement et tranforme la fonction
en une fonction de type AstPlacement.fonction *)
(* Erreur si mauvaise utilisation des identifiants *)
let analyse_placement_fonction (AstType.Fonction(info,li,b)) =
  let rec placement_aux l depl  = 
    match  l with 
      |[] -> []
      | info::q -> 
      match info_ast_to_info info with 
        | InfoVar (_,t, _, _) -> (modifier_adresse_variable (depl - getTaille t) "LB" info)::(placement_aux q (depl - getTaille t))
        | _ -> failwith "Erreur Interne"
  in
  let _ = placement_aux (List.rev li) 0 in  
  let nb = analyse_placement_bloc b 3 "LB" in 
  AstPlacement.Fonction(info,li,nb)



(* analyser : AstType.programme -> AstPlacement.programme *)
(* Paramètre : le programme à analyser *)
(* Placement mémoire de toutes le programme et tranforme le programme
en un programme de type AstTds.programme *)
let analyser (AstType.Programme (fonctions,bloc)) =
  let nf = List.map analyse_placement_fonction fonctions in 
  let nb = analyse_placement_bloc bloc 0 "SB" in
  AstPlacement.Programme(nf,nb)
