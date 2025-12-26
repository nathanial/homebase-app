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

def hasAnyUsers (ctx : Context) : Bool :=
  match ctx.database with
  | none => false
  | some db => !(db.entitiesWithAttr userEmail).isEmpty

/-! ## Login Views -/

def loginContent (ctx : Context) : HtmlM Unit := do
  div [class_ "bg-white rounded-xl shadow-lg p-8"] do
    h1 [class_ "text-2xl font-bold text-slate-800 mb-6"] (text "Login")
    form [method_ "post", action_ "/login"] do
      csrfField ctx.csrfToken
      div [class_ "mb-4"] do
        label [for_ "email", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Email")
        input [type_ "email", name_ "email", id_ "email", required_,
               placeholder_ "you@example.com",
               class_ "w-full px-4 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-colors"]
      div [class_ "mb-6"] do
        label [for_ "password", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Password")
        input [type_ "password", name_ "password", id_ "password", required_,
               placeholder_ "Your password",
               class_ "w-full px-4 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-colors"]
      button [type_ "submit", class_ "w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-lg transition-colors"] (text "Login")
    p [class_ "mt-4 text-center text-slate-500"] do
      text "Don't have an account? "
      a [href_ "/register", class_ "text-blue-600 hover:text-blue-700 font-medium"] (text "Register here")

/-! ## Register Views -/

def registerContent (ctx : Context) : HtmlM Unit := do
  div [class_ "bg-white rounded-xl shadow-lg p-8"] do
    h1 [class_ "text-2xl font-bold text-slate-800 mb-6"] (text "Create Account")
    form [method_ "post", action_ "/register"] do
      csrfField ctx.csrfToken
      div [class_ "mb-4"] do
        label [for_ "name", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Name")
        input [type_ "text", name_ "name", id_ "name", required_,
               placeholder_ "Your name",
               class_ "w-full px-4 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-colors"]
      div [class_ "mb-4"] do
        label [for_ "email", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Email")
        input [type_ "email", name_ "email", id_ "email", required_,
               placeholder_ "you@example.com",
               class_ "w-full px-4 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-colors"]
      div [class_ "mb-6"] do
        label [for_ "password", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Password")
        input [type_ "password", name_ "password", id_ "password", required_,
               placeholder_ "Choose a password",
               class_ "w-full px-4 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-colors"]
      button [type_ "submit", class_ "w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-lg transition-colors"] (text "Create Account")
    p [class_ "mt-4 text-center text-slate-500"] do
      text "Already have an account? "
      a [href_ "/login", class_ "text-blue-600 hover:text-blue-700 font-medium"] (text "Login here")

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
        modifyCtx fun c => c.withSession fun s =>
          s.set "user_id" (toString userId.id) |>.set "user_name" userName
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
    match ← allocEntityId with
    | none =>
      modifyCtx fun c => c.withFlash fun f => f.set "error" "Database not available"
      redirect "/register"
    | some userId =>
      let ctx ← getCtx  -- Get updated context after allocEntityId
      let passwordHash := hashPassword password ctx.config.secretKey
      let tx : Transaction := [
        .add userId userName (.string name),
        .add userId userEmail (.string email),
        .add userId userPasswordHash (.string passwordHash),
        .add userId userIsAdmin (.bool isFirstUser)
      ]
      match ← transact tx with
      | .ok () =>
        modifyCtx fun c => c.withSession fun s =>
          s.set "user_id" (toString userId.id) |>.set "user_name" name
        let adminNote := if isFirstUser then " You have been granted admin privileges." else ""
        modifyCtx fun c => c.withFlash fun f => f.set "success" s!"Welcome, {name}! Your account has been created.{adminNote}"
        redirect "/"
      | .error e =>
        modifyCtx fun c => c.withFlash fun f => f.set "error" s!"Failed to create account: {e}"
        redirect "/register"

page logout "/logout" GET do
  modifyCtx fun c => c.withSession fun s => s.clear
  modifyCtx fun c => c.withFlash fun f => f.set "info" "You have been logged out"
  redirect "/"

end HomebaseApp.Pages
