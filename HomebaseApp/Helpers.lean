/-
  HomebaseApp.Helpers - Auth guards, database utilities, password hashing
-/
import Loom
import Ledger
import Crypt
import HomebaseApp.Models

namespace HomebaseApp.Helpers

open Loom
open Ledger
open HomebaseApp.Models

/-! ## Password Hashing (Argon2id via libsodium) -/

/-- Hash a password using Argon2id for secure storage.
    Returns an encoded string containing salt and parameters. -/
def hashPassword (password : String) : IO (Except String String) := do
  let _ ← Crypt.init
  match ← Crypt.Password.hashStr password with
  | .ok hash => return .ok hash
  | .error e => return .error (toString e)

/-- Verify a password against a stored Argon2id hash -/
def verifyPassword (password storedHash : String) : IO Bool := do
  let _ ← Crypt.init
  Crypt.Password.verify password storedHash

/-! ## Auth Guards -/

/-- Require authentication - redirect to login if not authenticated -/
def requireAuth (handler : Action) : Action := fun ctx => do
  match ctx.session.get "user_id" with
  | none =>
    let ctx := ctx.withFlash fun f => f.set "error" "Please log in to continue"
    Action.redirect "/login" ctx
  | some _ => handler ctx

/-- Get current user ID from session -/
def currentUserId (ctx : Context) : Option String :=
  ctx.session.get "user_id"

/-- Get current user name from session -/
def currentUserName (ctx : Context) : Option String :=
  ctx.session.get "user_name"

/-- Check if user is logged in -/
def isLoggedIn (ctx : Context) : Bool :=
  ctx.session.has "user_id"

/-- Check if current user is an admin -/
def isAdmin (ctx : Context) : Bool :=
  match currentUserId ctx with
  | none => false
  | some idStr =>
    match idStr.toNat? with
    | none => false
    | some id =>
      let eid : EntityId := ⟨id⟩
      match ctx.database with
      | none => false
      | some db =>
        match db.getOne eid userIsAdmin with
        | some (.bool true) => true
        | _ => false

/-- Require admin privileges - redirect to home if not admin -/
def requireAdmin (handler : Action) : Action := fun ctx => do
  match ctx.session.get "user_id" with
  | none =>
    let ctx := ctx.withFlash fun f => f.set "error" "Please log in to continue"
    Action.redirect "/login" ctx
  | some idStr =>
    match idStr.toNat? with
    | none =>
      let ctx := ctx.withFlash fun f => f.set "error" "Invalid session"
      Action.redirect "/login" ctx
    | some id =>
      let eid : EntityId := ⟨id⟩
      match ctx.database with
      | none =>
        let ctx := ctx.withFlash fun f => f.set "error" "Database not available"
        Action.redirect "/" ctx
      | some db =>
        match db.getOne eid userIsAdmin with
        | some (.bool true) => handler ctx
        | _ =>
          let ctx := ctx.withFlash fun f => f.set "error" "Access denied. Admin privileges required."
          Action.redirect "/" ctx

/-- Check if any users exist in the database -/
def hasAnyUsers (ctx : Context) : Bool :=
  match ctx.database with
  | none => false
  | some db => !(db.entitiesWithAttr userEmail).isEmpty

/-- Get all users from the database -/
def getAllUsers (ctx : Context) : List (EntityId × String × String × Bool) :=
  match ctx.database with
  | none => []
  | some db =>
    let userIds := db.entitiesWithAttr userEmail
    userIds.filterMap fun uid =>
      match db.getOne uid userEmail, db.getOne uid userName with
      | some (.string email), some (.string name) =>
        let isAdminVal := match db.getOne uid userIsAdmin with
          | some (.bool b) => b
          | _ => false
        some (uid, email, name, isAdminVal)
      | _, _ => none

/-! ## Database Helpers -/

/-- Find user by email -/
def findUserByEmail (ctx : Context) (email : String) : Option EntityId :=
  ctx.database.bind fun db =>
    db.findOneByAttrValue userEmail (.string email)

/-- Find user by ID -/
def findUserById (ctx : Context) (id : String) : Option EntityId :=
  match id.toInt? with
  | some n => some ⟨n⟩
  | none => none

/-- Get a single attribute value as string -/
def getAttrString (ctx : Context) (entityId : EntityId) (attr : Attribute) : Option String :=
  ctx.database.bind fun db =>
    match db.getOne entityId attr with
    | some (.string s) => some s
    | _ => none

/-- Get a single attribute value as bool -/
def getAttrBool (ctx : Context) (entityId : EntityId) (attr : Attribute) : Option Bool :=
  ctx.database.bind fun db =>
    match db.getOne entityId attr with
    | some (.bool b) => some b
    | _ => none

-- Note: logAudit, logAuditWarn, and logAuditError are now provided by Loom.Audit

/-! ## Route Parameter Helpers -/

/-- Wrapper to extract :id parameter and pass to action -/
def withId (f : Nat → Action) : Action := fun ctx => do
  match ctx.params.get "id" with
  | none => Action.badRequest ctx "Missing ID parameter"
  | some idStr =>
    match idStr.toNat? with
    | none => Action.badRequest ctx "Invalid ID parameter"
    | some id => f id ctx

end HomebaseApp.Helpers
