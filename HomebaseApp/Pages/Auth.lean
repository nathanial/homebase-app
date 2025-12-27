/-
  HomebaseApp.Pages.Auth - Authentication pages (login, register, logout)
-/
import Scribe
import Loom
import Ledger
import HomebaseApp.Shared
import HomebaseApp.Models

namespace HomebaseApp.Pages

open Scribe
open Loom
open Loom.Page
open Loom.ActionM
open Ledger
open HomebaseApp.Shared
open HomebaseApp.Models

/-! ## Password Hashing (copied from Helpers to avoid circular deps) -/

private def polyHash (data : ByteArray) : Nat :=
  let prime : Nat := 31
  data.foldl (init := 0) fun hash byte =>
    hash * prime + byte.toNat

private def toHexString (n : Nat) : String :=
  String.ofList (n.toDigits 16)

def hashPassword (password : String) (secret : ByteArray) : String :=
  let passBytes := password.toUTF8
  let combined := secret ++ passBytes
  let hash1 := polyHash combined
  let hash1Str := toString hash1
  let hash2 := polyHash (combined ++ hash1Str.toUTF8)
  s!"{toHexString hash1}-{toHexString hash2}"

/-! ## User Lookups -/

def findUserByEmail (ctx : Context) (email : String) : Option EntityId :=
  match ctx.database with
  | none => none
  | some db =>
    db.findOneByAttrValue userEmail (.string email)

def getAttrString (ctx : Context) (eid : EntityId) (attr : Attribute) : Option String :=
  match ctx.database with
  | none => none
  | some db =>
    match db.getOne eid attr with
    | some (.string s) => some s
    | _ => none

def getAttrBool (ctx : Context) (eid : EntityId) (attr : Attribute) : Bool :=
  match ctx.database with
  | none => false
  | some db =>
    match db.getOne eid attr with
    | some (.bool b) => b
    | _ => false

def hasAnyUsers (ctx : Context) : Bool :=
  match ctx.database with
  | none => false
  | some db => !(db.entitiesWithAttr userEmail).isEmpty

/-! ## Login Views -/

def loginContent (ctx : Context) : HtmlM Unit := do
  div [class_ "auth-card"] do
    h1 [class_ "auth-title"] (text "Login")
    form [method_ "post", action_ "/login"] do
      csrfField ctx.csrfToken
      div [class_ "form-group-lg"] do
        label [for_ "email", class_ "form-label"] (text "Email")
        input [type_ "email", name_ "email", id_ "email", required_,
               placeholder_ "you@example.com",
               class_ "form-input"]
      div [class_ "form-group-lg"] do
        label [for_ "password", class_ "form-label"] (text "Password")
        input [type_ "password", name_ "password", id_ "password", required_,
               placeholder_ "Your password",
               class_ "form-input"]
      button [type_ "submit", class_ "btn btn-primary btn-block"] (text "Login")
    p [class_ "auth-footer"] do
      text "Don't have an account? "
      a [href_ "/register"] (text "Register here")

/-! ## Register Views -/

def registerContent (ctx : Context) : HtmlM Unit := do
  div [class_ "auth-card"] do
    h1 [class_ "auth-title"] (text "Create Account")
    form [method_ "post", action_ "/register"] do
      csrfField ctx.csrfToken
      div [class_ "form-group-lg"] do
        label [for_ "name", class_ "form-label"] (text "Name")
        input [type_ "text", name_ "name", id_ "name", required_,
               placeholder_ "Your name",
               class_ "form-input"]
      div [class_ "form-group-lg"] do
        label [for_ "email", class_ "form-label"] (text "Email")
        input [type_ "email", name_ "email", id_ "email", required_,
               placeholder_ "you@example.com",
               class_ "form-input"]
      div [class_ "form-group-lg"] do
        label [for_ "password", class_ "form-label"] (text "Password")
        input [type_ "password", name_ "password", id_ "password", required_,
               placeholder_ "Choose a password",
               class_ "form-input"]
      button [type_ "submit", class_ "btn btn-primary btn-block"] (text "Create Account")
    p [class_ "auth-footer"] do
      text "Already have an account? "
      a [href_ "/login"] (text "Login here")

/-! ## Auth Pages -/

page loginForm "/login" GET do
  let ctx ← getCtx
  if isLoggedIn ctx then
    return ← redirect "/"
  html (Shared.renderSimple ctx "Login - Homebase" (loginContent ctx))

page loginSubmit "/login" POST do
  let ctx ← getCtx
  let email := ctx.paramD "email" ""
  let password := ctx.paramD "password" ""

  if email.isEmpty || password.isEmpty then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Email and password are required"
    return ← redirect "/login"

  match findUserByEmail ctx email with
  | none =>
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Invalid email or password"
    redirect "/login"
  | some userId =>
    let storedHash := getAttrString ctx userId userPasswordHash
    let inputHash := hashPassword password ctx.config.secretKey
    match storedHash with
    | some hash =>
      if hash == inputHash then
        let userName := (getAttrString ctx userId userName).getD "User"
        let isAdminUser := getAttrBool ctx userId userIsAdmin
        modifyCtx fun c => c.withSession fun s =>
          s.set "user_id" (toString userId.id)
           |>.set "user_name" userName
           |>.set "is_admin" (if isAdminUser then "true" else "false")
        modifyCtx fun c => c.withFlash fun f => f.set "success" s!"Welcome back, {userName}!"
        redirect "/"
      else
        modifyCtx fun c => c.withFlash fun f => f.set "error" "Invalid email or password"
        redirect "/login"
    | none =>
      modifyCtx fun c => c.withFlash fun f => f.set "error" "Invalid email or password"
      redirect "/login"

page registerForm "/register" GET do
  let ctx ← getCtx
  if isLoggedIn ctx then
    return ← redirect "/"
  html (Shared.renderSimple ctx "Register - Homebase" (registerContent ctx))

page registerSubmit "/register" POST do
  let ctx ← getCtx
  let name := ctx.paramD "name" ""
  let email := ctx.paramD "email" ""
  let password := ctx.paramD "password" ""

  if name.isEmpty || email.isEmpty || password.isEmpty then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "All fields are required"
    return ← redirect "/register"

  match findUserByEmail ctx email with
  | some _ =>
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Email already registered"
    redirect "/register"
  | none =>
    let isFirstUser := !hasAnyUsers ctx
    let ctx ← getCtx
    let passwordHash := hashPassword password ctx.config.secretKey
    let (userId, _) ← withNewEntity! fun userId => do
      Ledger.TxM.addStr userId userName name
      Ledger.TxM.addStr userId userEmail email
      Ledger.TxM.addStr userId userPasswordHash passwordHash
      Ledger.TxM.addBool userId userIsAdmin isFirstUser
    modifyCtx fun c => c.withSession fun s =>
      s.set "user_id" (toString userId.id)
       |>.set "user_name" name
       |>.set "is_admin" (if isFirstUser then "true" else "false")
    let adminNote := if isFirstUser then " You have been granted admin privileges." else ""
    modifyCtx fun c => c.withFlash fun f => f.set "success" s!"Welcome, {name}! Your account has been created.{adminNote}"
    redirect "/"

page logout "/logout" GET do
  modifyCtx fun c => c.withSession fun s => s.clear
  modifyCtx fun c => c.withFlash fun f => f.set "info" "You have been logged out"
  redirect "/"

end HomebaseApp.Pages
