/-
  HomebaseApp.Actions.Admin - Admin panel actions for user management
-/
import Loom
import Ledger
import HomebaseApp.Models
import HomebaseApp.Helpers
import HomebaseApp.Views.Admin

namespace HomebaseApp.Actions.Admin

open Loom
open Ledger
open HomebaseApp.Models
open HomebaseApp.Helpers

/-- Admin dashboard - list all users -/
def index : Action := requireAdmin fun ctx => do
  let users := getAllUsers ctx
  let html := HomebaseApp.Views.Admin.renderUserList ctx users
  Action.html html ctx

/-- View a single user -/
def showUser (userId : Nat) : Action := requireAdmin fun ctx => do
  let eid : EntityId := ⟨userId⟩
  match getAttrString ctx eid userEmail, getAttrString ctx eid userName with
  | some email, some name =>
    let isAdminVal := match getAttrBool ctx eid userIsAdmin with
      | some b => b
      | none => false
    let html := HomebaseApp.Views.Admin.renderUserDetail ctx userId email name isAdminVal
    Action.html html ctx
  | _, _ => Action.notFound ctx "User not found"

/-- Show create user form -/
def createUserForm : Action := requireAdmin fun ctx => do
  let html := HomebaseApp.Views.Admin.renderCreateUserForm ctx
  Action.html html ctx

/-- Create a new user -/
def storeUser : Action := requireAdmin fun ctx => do
  let name := ctx.paramD "name" ""
  let email := ctx.paramD "email" ""
  let password := ctx.paramD "password" ""
  let isAdminParam := ctx.paramD "is_admin" ""

  if name.isEmpty || email.isEmpty || password.isEmpty then
    let ctx := ctx.withFlash fun f => f.set "error" "Name, email, and password are required"
    return ← Action.redirect "/admin/user/new" ctx

  match findUserByEmail ctx email with
  | some _ =>
    let ctx := ctx.withFlash fun f => f.set "error" "Email already registered"
    Action.redirect "/admin/user/new" ctx
  | none =>
    match ctx.allocEntityId with
    | none =>
      let ctx := ctx.withFlash fun f => f.set "error" "Database not available"
      Action.redirect "/admin" ctx
    | some (userId, ctx) =>
      let passwordHash := hashPassword password ctx.config.secretKey
      let isAdminVal := isAdminParam == "on" || isAdminParam == "true"
      let tx : Transaction := [
        .add userId userName (.string name),
        .add userId userEmail (.string email),
        .add userId userPasswordHash (.string passwordHash),
        .add userId userIsAdmin (.bool isAdminVal)
      ]
      match ← ctx.transact tx with
      | Except.ok ctx =>
        logAudit ctx "CREATE" "user" userId.id.toNat [("email", email), ("is_admin", toString isAdminVal)]
        let ctx := ctx.withFlash fun f => f.set "success" s!"User '{name}' created successfully"
        Action.redirect "/admin" ctx
      | Except.error e =>
        let ctx := ctx.withFlash fun f => f.set "error" s!"Failed to create user: {e}"
        Action.redirect "/admin/user/new" ctx

/-- Show edit user form -/
def editUserForm (userId : Nat) : Action := requireAdmin fun ctx => do
  let eid : EntityId := ⟨userId⟩
  match getAttrString ctx eid userEmail, getAttrString ctx eid userName with
  | some email, some name =>
    let isAdminVal := match getAttrBool ctx eid userIsAdmin with
      | some b => b
      | none => false
    let html := HomebaseApp.Views.Admin.renderEditUserForm ctx userId email name isAdminVal
    Action.html html ctx
  | _, _ => Action.notFound ctx "User not found"

/-- Update a user -/
def updateUser (userId : Nat) : Action := requireAdmin fun ctx => do
  let name := ctx.paramD "name" ""
  let email := ctx.paramD "email" ""
  let password := ctx.paramD "password" ""
  let isAdminParam := ctx.paramD "is_admin" ""

  if name.isEmpty || email.isEmpty then
    let ctx := ctx.withFlash fun f => f.set "error" "Name and email are required"
    return ← Action.redirect s!"/admin/user/{userId}/edit" ctx

  let eid : EntityId := ⟨userId⟩

  -- Check if email is taken by another user
  match findUserByEmail ctx email with
  | some existingId =>
    if existingId.id.toNat != userId then
      let ctx := ctx.withFlash fun f => f.set "error" "Email already taken by another user"
      return ← Action.redirect s!"/admin/user/{userId}/edit" ctx
  | none => pure ()

  match ctx.database with
  | none =>
    let ctx := ctx.withFlash fun f => f.set "error" "Database not available"
    Action.redirect "/admin" ctx
  | some db =>
    let isAdminVal := isAdminParam == "on" || isAdminParam == "true"

    -- Build update transaction with retractions
    let mut tx : Transaction := []

    -- Retract and add name
    match db.getOne eid userName with
    | some oldVal => tx := tx ++ [.retract eid userName oldVal]
    | none => pure ()
    tx := tx ++ [.add eid userName (.string name)]

    -- Retract and add email
    match db.getOne eid userEmail with
    | some oldVal => tx := tx ++ [.retract eid userEmail oldVal]
    | none => pure ()
    tx := tx ++ [.add eid userEmail (.string email)]

    -- Retract and add isAdmin
    match db.getOne eid userIsAdmin with
    | some oldVal => tx := tx ++ [.retract eid userIsAdmin oldVal]
    | none => pure ()
    tx := tx ++ [.add eid userIsAdmin (.bool isAdminVal)]

    -- Update password only if provided
    if !password.isEmpty then
      let passwordHash := hashPassword password ctx.config.secretKey
      match db.getOne eid userPasswordHash with
      | some oldVal => tx := tx ++ [.retract eid userPasswordHash oldVal]
      | none => pure ()
      tx := tx ++ [.add eid userPasswordHash (.string passwordHash)]

    match ← ctx.transact tx with
    | Except.ok ctx =>
      logAudit ctx "UPDATE" "user" userId [("email", email)]
      let ctx := ctx.withFlash fun f => f.set "success" s!"User '{name}' updated successfully"
      Action.redirect "/admin" ctx
    | Except.error e =>
      let ctx := ctx.withFlash fun f => f.set "error" s!"Failed to update user: {e}"
      Action.redirect s!"/admin/user/{userId}/edit" ctx

/-- Delete a user -/
def deleteUser (userId : Nat) : Action := requireAdmin fun ctx => do
  -- Prevent self-deletion
  match currentUserId ctx with
  | some currentId =>
    if currentId == toString userId then
      let ctx := ctx.withFlash fun f => f.set "error" "You cannot delete your own account"
      return ← Action.redirect "/admin" ctx
  | none => pure ()

  let eid : EntityId := ⟨userId⟩

  match ctx.database with
  | none =>
    let ctx := ctx.withFlash fun f => f.set "error" "Database not available"
    Action.redirect "/admin" ctx
  | some db =>
    -- Get user info for audit before deletion
    let userEmailStr := match getAttrString ctx eid userEmail with
      | some e => e
      | none => "(unknown)"

    -- Build retraction transaction
    let mut tx : Transaction := []
    match db.getOne eid userName with
    | some val => tx := tx ++ [.retract eid userName val]
    | none => pure ()
    match db.getOne eid userEmail with
    | some val => tx := tx ++ [.retract eid userEmail val]
    | none => pure ()
    match db.getOne eid userPasswordHash with
    | some val => tx := tx ++ [.retract eid userPasswordHash val]
    | none => pure ()
    match db.getOne eid userIsAdmin with
    | some val => tx := tx ++ [.retract eid userIsAdmin val]
    | none => pure ()

    match ← ctx.transact tx with
    | Except.ok ctx =>
      logAudit ctx "DELETE" "user" userId [("email", userEmailStr)]
      let ctx := ctx.withFlash fun f => f.set "success" "User deleted successfully"
      Action.redirect "/admin" ctx
    | Except.error e =>
      logAuditError ctx "DELETE" "user" [("user_id", toString userId), ("error", toString e)]
      let ctx := ctx.withFlash fun f => f.set "error" s!"Failed to delete user: {e}"
      Action.redirect "/admin" ctx

end HomebaseApp.Actions.Admin
