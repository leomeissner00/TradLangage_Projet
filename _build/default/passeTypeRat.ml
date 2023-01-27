(* Module de typage des identifiants *)
(* doit être conforme à l'interface Passe *)
open Tds
open Ast
open Exceptions
open Type

type t1 = Ast.AstTds.programme
type t2 = Ast.AstType.programme

(*Fonction permettant de récupérer le type contenu dans une info_ast : info_ast -> typ
   Paramètre info : info_ast dont on veut récupérer le paramètre
   Type d'une info_ast
   Erreur si mauvaise utilisation d'un identifiant*)
let getType info =
  match info_ast_to_info info with
    | InfoVar (_,t,_,_)-> t
    | InfoConst _ -> Int
    | InfoFun _ -> failwith "Mauvaise utilisation d'une fonction"
    | InfoLoop _ -> failwith " Mauvaise utilisation break"

(*analyse_type_affectable : AstTds.affectbale -> AstType.affectable * typ
   Paramètre : a : affectable à analyser
   Analyse des expressions
   Erreur si mauvaise utilisation d'un affectable*)
let rec analyse_type_affectable a =
  match a with
  | AstTds.Valeur v ->
    begin
      match analyse_type_affectable v with
      |(na, Pointeur t) -> (AstType.Valeur na, t)
      | _ -> failwith "Ce n'est pas un pointeur"
    end
  | AstTds.Ident info ->
    begin
      match info_ast_to_info info with
      | InfoVar (_,t,_,_) -> (AstType.Ident info, t)
      | InfoConst _ -> (AstType.Ident info, Int)
      | _ -> failwith "Erreur dans analyse type affectable"
    end

(* analyse_type_expression : AstTds.expression -> AstType.expression*type *)
(* Paramètre e : l'expression à analyser *)
(* Typage des expressions *)
(* Erreur si mauvaise utilisation des identifiants *)
let rec analyse_type_expression e = 
  match e with
  | AstTds.Ident info -> (AstType.Ident (info), getType info)
  | AstTds.Entier i -> (AstType.Entier i, Int)
  | AstTds.Booleen b -> (AstType.Booleen b, Bool)
  | AstTds.Binaire (b, e1, e2) -> 
    let (ne1, t1) = analyse_type_expression e1 in
    let (ne2, t2) = analyse_type_expression e2 in
    begin
    match b,t1,t2 with
    | Plus, Int, Int -> (AstType.Binaire (PlusInt, ne1, ne2), Int)
    | Plus, Rat, Rat -> (AstType.Binaire (PlusRat, ne1, ne2), Rat)
    | Mult, Int, Int -> (AstType.Binaire (MultInt, ne1, ne2), Int)
    | Mult, Rat, Rat -> (AstType.Binaire (MultRat, ne1, ne2), Rat)
    | Fraction, Int, Int -> (AstType.Binaire (Fraction, ne1, ne2), Rat)
    | Equ, Int, Int -> (AstType.Binaire (EquInt, ne1, ne2), Bool)
    | Equ, Bool, Bool -> (AstType.Binaire (EquBool, ne1, ne2), Bool)
    | Inf, Int, Int -> (AstType.Binaire (Inf, ne1, ne2), Bool)
    | _ -> raise(TypeBinaireInattendu(b,t1,t2))
    end
  | AstTds.Unaire (u, e) -> 
    let (ne, t) = analyse_type_expression e in
    if est_compatible t Rat then
      begin
        match u with
        | Numerateur -> (AstType.Unaire (Numerateur, ne), Int)
        | Denominateur -> (AstType.Unaire (Denominateur, ne), Int)
      end
    else
      raise(TypeInattendu(t,Rat))

  | AstTds.AppelFonction (s, l) ->
    let le = List.map analyse_type_expression l in
    let l' = List.fold_right (fun (info,_) liste -> info::liste) le [] in
    let t' = List.fold_right (fun (_,t) liste -> t::liste) le [] in
    begin
    match info_ast_to_info s with
      | InfoFun (_,t,tl) -> 
        if est_compatible_list t' tl then (AstType.AppelFonction (s,l'),t) 
        else raise(TypesParametresInattendus(t', tl))
      | _ -> failwith "Erreur de type dans une expression de type appel de fonction"
      end
  | AstTds.Null -> AstType.Null, Pointeur Undefined
  | AstTds.New t -> (New t, Pointeur t)
  | AstTds.Affectable a ->
    let (na, t) = analyse_type_affectable a in
    (AstType.Affectable na, t)
  | AstTds.Adresse info ->
    begin
      match info_ast_to_info info with
      | InfoVar (_,t,_,_) -> AstType.Adresse info, Pointeur t
      | _ -> failwith "Erreur dans analyse expression avec une adresse"
    end
  | AstTds.Ternaire (e1, e2, e3) ->
    let (ne1, t1) = analyse_type_expression e1 in
    let (ne2, t2) = analyse_type_expression e2 in
    let (ne3, t3) = analyse_type_expression e3 in
    if est_compatible t1 Bool then
      if est_compatible t2 t3 then
        AstType.Ternaire(ne1, ne2, ne3), t2
      else 
        raise(TypeInattendu(t2,t3))
    else
      raise(TypeInattendu(t1, Bool)) 

 
(* analyse_type_instruction : AstTds.instruction -> AstType.instruction *)
(* Paramètre i : l'instruction à analyser *)
(* Vérifie le bon typage de l'instruction *)
(* Erreur si mauvaise utilisation des identifiants *)
let rec analyse_type_instruction i =
  match i with
  | AstTds.Declaration (t, info, e) ->
    let (ne, te) = analyse_type_expression e in
    if est_compatible te t then
      (modifier_type_variable t info;
      AstType.Declaration (info, ne))
    else raise(TypeInattendu(te,t))

  | AstTds.Affectation (a,e) ->
    let (na, ta) = analyse_type_affectable a in
    let (ne, te) = analyse_type_expression e in
    if est_compatible ta te then
      AstType.Affectation(na, ne)
    else
      raise(TypeInattendu (te, ta))

  | AstTds.Affichage e ->
    let (ne, te) = analyse_type_expression e in
    begin
    match te with
    | Int -> AstType.AffichageInt ne
    | Rat -> AstType.AffichageRat ne
    | Bool -> AstType.AffichageBool ne
    | Pointeur _ -> AstType.AffichagePoint ne
    | _ -> raise(TypeInattendu(te, te))
    end
  | AstTds.Conditionnelle (e,b1,b2) ->
    let (ne, te) = analyse_type_expression e in
    if est_compatible te Bool then
      let nb1 = analyse_type_bloc b1 in
      let nb2 = analyse_type_bloc b2 in
      AstType.Conditionnelle (ne, nb1, nb2)
    else raise(TypeInattendu(te,Bool))
  | AstTds.ConditionnelleOptionnelle (e,b) ->
    let (ne, te) = analyse_type_expression e in
    if est_compatible te Bool then
      let nb1 = analyse_type_bloc b in
      AstType.ConditionnelleOptionnelle (ne, nb1)
    else raise(TypeInattendu(te,Bool))
  | AstTds.TantQue (c,b) ->
    let (nc, tc) = analyse_type_expression c in
    if est_compatible tc Bool then
      let nb = analyse_type_bloc b in
      AstType.TantQue (nc, nb)
    else raise(TypeInattendu(tc, Bool))
  | AstTds.Retour (e, info) ->
    let (ne, te) = analyse_type_expression e in
    begin
      match info_ast_to_info info with
      | InfoFun(_,nt,_) -> if est_compatible nt te 
        then AstType.Retour(ne,info)
    else raise (TypeInattendu(te,nt))
      | _ -> failwith "Erreur retour Type"
    end
  | AstTds.Empty -> AstType.Empty
  | AstTds.Loop(iaBreak,b) -> AstType.Loop(iaBreak, analyse_type_bloc b)
  | AstTds.Break(id) -> AstType.Break(id)
  | AstTds.Continue(id) -> AstType.Continue(id)


(* analyse_Type_bloc : AstTds.bloc -> AstType.bloc *)
(* Paramètre li : liste d'instructions à analyser *)
(* Effectue le typage des élements du bloc et tranforme le bloc en un bloc de type AstType.bloc *)
and analyse_type_bloc li = List.map analyse_type_instruction li

(* analyse_type_fonction : AstTds.fonction -> AstType.fonction *)
(* Paramètre : la fonction à analyser *)
(* Typage de la fonction et de ses paramètres et tranforme la fonction
en une fonction de type AstType.fonction *)
(* Erreur si mauvaise utilisation des identifiants *)
let analyse_t_fonction (AstTds.Fonction(t,info,lp,bloc)) =
  List.iter (fun (t,info) -> (modifier_type_variable t info)) lp;
  let lt = List.map (fun (t,_) -> t) lp in
  modifier_type_fonction t lt info;
  let nbloc = analyse_type_bloc bloc in
  let linfo = List.map (fun (_,info) -> info) lp in
  AstType.Fonction(info,linfo,nbloc)

(* analyser : AstSyntax.programme -> AstTds.programme *)
(* Paramètre : le programme à analyser *)
(* Vérifie la bonne utilisation des identifiants et tranforme le  programme
en un programme de type AstTds.programme *)
(* Erreur si mauvaise utilisation des identifiants *)
let analyser (AstTds.Programme (fonctions,prog)) =
  let nf = List.map (analyse_t_fonction) fonctions in
  let nb = analyse_type_bloc prog in
  AstType.Programme (nf,nb)
