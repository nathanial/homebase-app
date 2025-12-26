/-
  HomebaseApp.Helpers - Auth guards, database utilities, password hashing
-/
import Loom
import Ledger
import Chronicle
import HomebaseApp.Models

namespace HomebaseApp.Helpers

open Loom
open Ledger
open HomebaseApp.Models

/-! ## Password Hashing -/

/-- Simple polynomial hash (demo only - use bcrypt/argon2 in production) -/
private def polyHash (data : ByteArray) : Nat :=
  let prime : Nat := 31
  data.foldl (init := 0) fun hash byte =>
    hash * prime + byte.toNat

/-- Convert Nat to hex string -/
private def toHexString (n : Nat) : String :=
  let hex := n.toDigits 16
  String.mk hex

/-- Hash a password with the app secret -/
def hashPassword (password : String) (secret : ByteArray) : String :=
  let passBytes := password.toUTF8
  let combined := secret ++ passBytes
  let hash1 := polyHash combined
  let hash1Str := toString hash1
  let hash2 := polyHash (combined ++ hash1Str.toUTF8)
  s!"{toHexString hash1}-{toHexString hash2}"

/-- Verify a password against a hash -/
def verifyPassword (password hash : String) (secret : ByteArray) : Bool :=
  hashPassword password secret == hash

/-! ## Auth Guards -/

/-- Require authentication - redirect to login if not authenticated -/
def requireAuth (action : Action) : Action := fun ctx => do
  match ctx.session.get "user_id" with
  | none =>
    let ctx := ctx.withFlash fun f => f.set "error" "Please log in to continue"
    Action.redirect "/login" ctx
  | some _ => action ctx

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
def requireAdmin (action : Action) : Action := fun ctx => do
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
        | some (.bool true) => action ctx
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

/-! ## Audit Logging -/

/-- Log an audit event with full context (user, entity, operation) -/
def logAudit (ctx : Context) (op : String) (entity : String) (entityId : Nat)
    (details : List (String × String) := []) : IO Unit := do
  match ctx.logger with
  | none => pure ()
  | some logger =>
    let userId := currentUserId ctx |>.getD "anonymous"
    let entry : Chronicle.LogEntry := {
      timestamp := ← IO.monoNanosNow
      level := .info
      message := s!"[AUDIT] {op} {entity}"
      context := [("user_id", userId), ("entity_id", toString entityId)] ++ details
    }
    Chronicle.MultiLogger.logRequest logger entry

/-- Log a warning audit event -/
def logAuditWarn (ctx : Context) (op : String) (entity : String) (entityId : Nat)
    (details : List (String × String) := []) : IO Unit := do
  match ctx.logger with
  | none => pure ()
  | some logger =>
    let userId := currentUserId ctx |>.getD "anonymous"
    let entry : Chronicle.LogEntry := {
      timestamp := ← IO.monoNanosNow
      level := .warn
      message := s!"[AUDIT] {op} {entity}"
      context := [("user_id", userId), ("entity_id", toString entityId)] ++ details
    }
    Chronicle.MultiLogger.logRequest logger entry

/-- Log an error audit event -/
def logAuditError (ctx : Context) (op : String) (entity : String)
    (details : List (String × String) := []) : IO Unit := do
  match ctx.logger with
  | none => pure ()
  | some logger =>
    let userId := currentUserId ctx |>.getD "anonymous"
    let entry : Chronicle.LogEntry := {
      timestamp := ← IO.monoNanosNow
      level := .error
      message := s!"[AUDIT] {op} {entity} FAILED"
      context := [("user_id", userId)] ++ details
    }
    Chronicle.MultiLogger.logRequest logger entry

end HomebaseApp.Helpers
