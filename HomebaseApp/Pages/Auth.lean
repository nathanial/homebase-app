/-
  HomebaseApp.Pages.Auth - Authentication pages (login, register, logout)
-/
import Loom
import Loom.Stencil
import Stencil
import Ledger
import Crypt
import HomebaseApp.Shared
import HomebaseApp.Models

namespace HomebaseApp.Pages

open Loom
open Loom.Page
open Loom.ActionM
open Ledger
open HomebaseApp.Shared
open HomebaseApp.Models

/-! ## Password Hashing (Argon2id via libsodium) -/

/-- Hash a password using Argon2id for secure storage -/
def hashPassword (password : String) : IO (Except String String) := do
  let _ ← Crypt.init
  match ← Crypt.Password.hashStr password with
  | .ok hash => return .ok hash
  | .error e => return .error (toString e)

/-- Verify a password against a stored Argon2id hash -/
def verifyPassword (password storedHash : String) : IO Bool := do
  let _ ← Crypt.init
  Crypt.Password.verify password storedHash

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

/-! ## Auth Pages -/

page loginForm "/login" GET do
  let ctx ← getCtx
  if isLoggedIn ctx then
    return ← redirect "/"
  let data : Stencil.Value := .object #[("title", .string "Login")]
  Loom.Stencil.ActionM.renderWithLayout "auth" "auth/login" data

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
    match storedHash with
    | some hash =>
      let valid ← verifyPassword password hash
      if valid then
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
  let data : Stencil.Value := .object #[("title", .string "Register")]
  Loom.Stencil.ActionM.renderWithLayout "auth" "auth/register" data

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
    match ← hashPassword password with
    | .error e =>
      modifyCtx fun c => c.withFlash fun f => f.set "error" s!"Password hashing failed: {e}"
      redirect "/register"
    | .ok passwordHash =>
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
