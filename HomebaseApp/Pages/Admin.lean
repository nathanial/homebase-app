/-
  HomebaseApp.Pages.Admin - Admin panel for user management
-/
import Loom
import Loom.Stencil
import Stencil
import Ledger
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Helpers
import HomebaseApp.Middleware
import HomebaseApp.StencilHelpers

namespace HomebaseApp.Pages

open Loom hiding Action
open Loom.Page
open Loom.ActionM
open Loom.AuditTxM (audit)
open Ledger
open HomebaseApp.Shared hiding isLoggedIn isAdmin
open HomebaseApp.Models
open HomebaseApp.Entities
open HomebaseApp.Helpers hiding isLoggedIn isAdmin
open HomebaseApp.StencilHelpers

/-! ## Database Helpers -/

/-- Get all users from the database -/
def getUsers (ctx : Context) : List (EntityId × DbUser) :=
  match ctx.database with
  | none => []
  | some db =>
    let userIds := db.entitiesWithAttr DbUser.attr_email
    let users := userIds.filterMap fun uid =>
      match DbUser.pull db uid with
      | some u => some (uid, u)
      | none => none
    users.toArray.qsort (fun a b => a.2.name < b.2.name) |>.toList

/-- Get a specific user by ID -/
def getUser (ctx : Context) (userId : Nat) : Option DbUser :=
  ctx.database.bind fun db => DbUser.pull db ⟨userId⟩

/-- Find user by email -/
def findUserByEmail' (ctx : Context) (email : String) : Option EntityId :=
  ctx.database.bind fun db =>
    db.findOneByAttrValue DbUser.attr_email (.string email)

/-! ## Stencil Value Helpers -/

/-- Convert a DbUser to Stencil.Value -/
def userToValue (uid : Nat) (user : DbUser) : Stencil.Value :=
  .object #[
    ("id", .int (Int.ofNat uid)),
    ("name", .string user.name),
    ("email", .string user.email),
    ("isAdmin", .bool user.isAdmin)
  ]

/-- Convert a list of users to Stencil.Value -/
def usersToValue (users : List (EntityId × DbUser)) : Stencil.Value :=
  .array (users.map fun (eid, user) => userToValue eid.id.toNat user).toArray

/-! ## Pages -/

-- User list
view admin "/admin" [HomebaseApp.Middleware.authRequired, HomebaseApp.Middleware.adminRequired] do
  let ctx ← getCtx
  let users := getUsers ctx
  let data := pageContext ctx "User Management" PageId.admin
    (.object #[("users", usersToValue users)])
  Loom.Stencil.ActionM.renderWithLayout "app" "admin/index" data

-- View user
view adminUser "/admin/user/:id" [HomebaseApp.Middleware.authRequired, HomebaseApp.Middleware.adminRequired] (id : Nat) do
  let ctx ← getCtx
  match getUser ctx id with
  | some user =>
    let data := pageContext ctx s!"User: {user.name}" PageId.admin
      (.object #[("user", userToValue id user)])
    Loom.Stencil.ActionM.renderWithLayout "app" "admin/show" data
  | none => notFound "User not found"

-- Create user form
view adminCreateUser "/admin/user/new" [HomebaseApp.Middleware.authRequired, HomebaseApp.Middleware.adminRequired] do
  let ctx ← getCtx
  let data := pageContext ctx "Create User" PageId.admin
  Loom.Stencil.ActionM.renderWithLayout "app" "admin/new" data

-- Store user
action adminStoreUser "/admin/user" POST [HomebaseApp.Middleware.authRequired, HomebaseApp.Middleware.adminRequired] do
  let ctx ← getCtx
  let name := ctx.paramD "name" ""
  let email := ctx.paramD "email" ""
  let password := ctx.paramD "password" ""
  let isAdminParam := ctx.paramD "is_admin" ""
  if name.isEmpty || email.isEmpty || password.isEmpty then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Name, email, and password are required"
    return ← redirect "/admin/user/new"
  match findUserByEmail' ctx email with
  | some _ =>
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Email already registered"
    redirect "/admin/user/new"
  | none =>
    match ← hashPassword password with
    | .error e =>
      modifyCtx fun c => c.withFlash fun f => f.set "error" s!"Password hashing failed: {e}"
      redirect "/admin/user/new"
    | .ok passwordHash =>
      let isAdminVal := isAdminParam == "on" || isAdminParam == "true"
      let (_, _) ← withNewEntityAudit! fun eid => do
        let dbUser : DbUser := {
          id := eid.id.toNat, email := email, passwordHash := passwordHash,
          name := name, isAdmin := isAdminVal
        }
        DbUser.TxM.create eid dbUser
        audit "CREATE" "user" eid.id.toNat [("email", email), ("name", name), ("is_admin", toString isAdminVal)]
      modifyCtx fun c => c.withFlash fun f => f.set "success" s!"User '{name}' created successfully"
      redirect "/admin"

-- Edit user form
view adminEditUser "/admin/user/:id/edit" [HomebaseApp.Middleware.authRequired, HomebaseApp.Middleware.adminRequired] (id : Nat) do
  let ctx ← getCtx
  match getUser ctx id with
  | some user =>
    let data := pageContext ctx s!"Edit User: {user.name}" PageId.admin
      (.object #[("user", userToValue id user)])
    Loom.Stencil.ActionM.renderWithLayout "app" "admin/edit" data
  | none => notFound "User not found"

-- Update user
action adminUpdateUser "/admin/user/:id" PUT [HomebaseApp.Middleware.authRequired, HomebaseApp.Middleware.adminRequired] (id : Nat) do
  let ctx ← getCtx
  let name := ctx.paramD "name" ""
  let email := ctx.paramD "email" ""
  let password := ctx.paramD "password" ""
  let isAdminParam := ctx.paramD "is_admin" ""
  if name.isEmpty || email.isEmpty then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Name and email are required"
    return ← redirect s!"/admin/user/{id}/edit"
  let eid : EntityId := ⟨id⟩
  -- Check if email is taken by another user
  match findUserByEmail' ctx email with
  | some existingId =>
    if existingId.id.toNat != id then
      modifyCtx fun c => c.withFlash fun f => f.set "error" "Email already taken by another user"
      return ← redirect s!"/admin/user/{id}/edit"
  | none => pure ()
  let isAdminVal := isAdminParam == "on" || isAdminParam == "true"
  -- Hash password before transaction (if provided)
  let passwordHashOpt ← if !password.isEmpty then do
    match ← hashPassword password with
    | .error e =>
      modifyCtx fun c => c.withFlash fun f => f.set "error" s!"Password hashing failed: {e}"
      return ← redirect s!"/admin/user/{id}/edit"
    | .ok h => pure (some h)
  else pure none
  runAuditTx! do
    let db ← AuditTxM.getDb
    let (oldEmail, oldName, oldIsAdmin) := match DbUser.pull db eid with
      | some u => (u.email, u.name, u.isAdmin)
      | none => ("", "", false)
    DbUser.TxM.setEmail eid email
    DbUser.TxM.setName eid name
    DbUser.TxM.setIsAdmin eid isAdminVal
    if let some passwordHash := passwordHashOpt then
      DbUser.TxM.setPasswordHash eid passwordHash
    let changes :=
      (if oldEmail != email then [("old_email", oldEmail), ("new_email", email)] else []) ++
      (if oldName != name then [("old_name", oldName), ("new_name", name)] else []) ++
      (if oldIsAdmin != isAdminVal then [("old_is_admin", toString oldIsAdmin), ("new_is_admin", toString isAdminVal)] else []) ++
      (if passwordHashOpt.isSome then [("password_changed", "true")] else [])
    audit "UPDATE" "user" id changes
  modifyCtx fun c => c.withFlash fun f => f.set "success" s!"User '{name}' updated successfully"
  redirect "/admin"

-- Delete user
action adminDeleteUser "/admin/user/:id" DELETE [HomebaseApp.Middleware.authRequired, HomebaseApp.Middleware.adminRequired] (id : Nat) do
  let ctx ← getCtx
  -- Check if trying to delete own account
  match currentUserId ctx with
  | some currentId =>
    if currentId == toString id then
      modifyCtx fun c => c.withFlash fun f => f.set "error" "You cannot delete your own account"
      return ← redirect "/admin"
  | none => pure ()
  let eid : EntityId := ⟨id⟩
  let userName := match getUser ctx id with
    | some u => u.name
    | none => "(unknown)"
  runAuditTx! do
    DbUser.TxM.delete eid
    audit "DELETE" "user" id [("name", userName)]
  modifyCtx fun c => c.withFlash fun f => f.set "success" "User deleted successfully"
  redirect "/admin"

end HomebaseApp.Pages
