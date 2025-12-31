/-
  HomebaseApp.Pages.Admin - Admin panel for user management
-/
import Scribe
import Loom
import Ledger
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Helpers
import HomebaseApp.Middleware

namespace HomebaseApp.Pages

open Scribe
open Loom hiding Action
open Loom.Page
open Loom.ActionM
open Loom.AuditTxM (audit)
open Ledger
open HomebaseApp.Shared hiding isLoggedIn isAdmin
open HomebaseApp.Models
open HomebaseApp.Entities
open HomebaseApp.Helpers hiding isLoggedIn isAdmin

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

/-! ## View Helpers -/

def userListContent (_ctx : Context) (users : List (EntityId × DbUser)) : HtmlM Unit := do
  div [class_ "admin-container"] do
    div [class_ "admin-header"] do
      h1 [class_ "admin-title"] (text "User Management")
      a [href_ "/admin/user/new", class_ "btn btn-primary"] (text "+ Add User")
    div [class_ "table-container"] do
      table [class_ "table"] do
        thead [] do
          tr [] do
            th [] (text "ID")
            th [] (text "Name")
            th [] (text "Email")
            th [] (text "Admin")
            th [] (text "Actions")
        tbody [] do
          for (eid, user) in users do
            tr [] do
              td [] (text (toString eid.id.toNat))
              td [] (text user.name)
              td [] (text user.email)
              td [] do
                if user.isAdmin then
                  span [class_ "badge badge-success"] (text "Yes")
                else
                  span [class_ "badge badge-secondary"] (text "No")
              td [class_ "table-actions"] do
                a [href_ s!"/admin/user/{eid.id.toNat}", class_ "btn btn-sm btn-secondary"]
                  (text "View")
                a [href_ s!"/admin/user/{eid.id.toNat}/edit", class_ "btn btn-sm btn-primary"]
                  (text "Edit")
                button [class_ "btn btn-sm btn-danger",
                        attr_ "hx-delete" s!"/admin/user/{eid.id.toNat}",
                        attr_ "hx-confirm" "Are you sure you want to delete this user?",
                        attr_ "hx-target" "body"]
                  (text "Delete")

def userDetailContent (_ctx : Context) (userId : Nat) (user : DbUser) : HtmlM Unit := do
  div [class_ "admin-container"] do
    div [class_ "admin-header"] do
      h1 [class_ "admin-title"] (text s!"User: {user.name}")
      div [class_ "admin-actions"] do
        a [href_ s!"/admin/user/{userId}/edit", class_ "btn btn-primary"] (text "Edit")
        a [href_ "/admin", class_ "btn btn-secondary"] (text "Back to List")
    div [class_ "card"] do
      dl [class_ "detail-list"] do
        dt [] (text "ID")
        dd [] (text (toString userId))
        dt [] (text "Name")
        dd [] (text user.name)
        dt [] (text "Email")
        dd [] (text user.email)
        dt [] (text "Admin")
        dd [] do
          if user.isAdmin then
            span [class_ "badge badge-success"] (text "Yes")
          else
            span [class_ "badge badge-secondary"] (text "No")

def createUserContent (ctx : Context) : HtmlM Unit := do
  div [class_ "admin-container"] do
    div [class_ "admin-header"] do
      h1 [class_ "admin-title"] (text "Create User")
      a [href_ "/admin", class_ "btn btn-secondary"] (text "Back to List")
    div [class_ "card"] do
      form [method_ "POST", action_ "/admin/user"] do
        csrfField ctx.csrfToken
        div [class_ "form-stack"] do
          div [class_ "form-group"] do
            label [for_ "name", class_ "form-label"] (text "Name")
            input [type_ "text", name_ "name", id_ "name",
                   class_ "form-input", required_, autofocus_,
                   placeholder_ "User's name"]
          div [class_ "form-group"] do
            label [for_ "email", class_ "form-label"] (text "Email")
            input [type_ "email", name_ "email", id_ "email",
                   class_ "form-input", required_,
                   placeholder_ "user@example.com"]
          div [class_ "form-group"] do
            label [for_ "password", class_ "form-label"] (text "Password")
            input [type_ "password", name_ "password", id_ "password",
                   class_ "form-input", required_,
                   placeholder_ "Choose a password"]
          div [class_ "form-group form-checkbox"] do
            input [type_ "checkbox", name_ "is_admin", id_ "is_admin"]
            label [for_ "is_admin", class_ "form-label"] (text "Grant admin privileges")
          div [class_ "form-actions"] do
            button [type_ "submit", class_ "btn btn-primary"] (text "Create User")
            a [href_ "/admin", class_ "btn btn-secondary"] (text "Cancel")

def editUserContent (ctx : Context) (userId : Nat) (user : DbUser) : HtmlM Unit := do
  div [class_ "admin-container"] do
    div [class_ "admin-header"] do
      h1 [class_ "admin-title"] (text s!"Edit User: {user.name}")
      a [href_ "/admin", class_ "btn btn-secondary"] (text "Back to List")
    div [class_ "card"] do
      form [method_ "POST", action_ s!"/admin/user/{userId}"] do
        input [type_ "hidden", name_ "_method", value_ "PUT"]
        csrfField ctx.csrfToken
        div [class_ "form-stack"] do
          div [class_ "form-group"] do
            label [for_ "name", class_ "form-label"] (text "Name")
            input [type_ "text", name_ "name", id_ "name", value_ user.name,
                   class_ "form-input", required_]
          div [class_ "form-group"] do
            label [for_ "email", class_ "form-label"] (text "Email")
            input [type_ "email", name_ "email", id_ "email", value_ user.email,
                   class_ "form-input", required_]
          div [class_ "form-group"] do
            label [for_ "password", class_ "form-label"] (text "Password (leave blank to keep current)")
            input [type_ "password", name_ "password", id_ "password",
                   class_ "form-input",
                   placeholder_ "Leave blank to keep current password"]
          div [class_ "form-group form-checkbox"] do
            if user.isAdmin then
              input [type_ "checkbox", name_ "is_admin", id_ "is_admin", checked_]
            else
              input [type_ "checkbox", name_ "is_admin", id_ "is_admin"]
            label [for_ "is_admin", class_ "form-label"] (text "Admin privileges")
          div [class_ "form-actions"] do
            button [type_ "submit", class_ "btn btn-primary"] (text "Save Changes")
            a [href_ "/admin", class_ "btn btn-secondary"] (text "Cancel")

/-! ## Pages -/

-- User list
view admin "/admin" [HomebaseApp.Middleware.authRequired, HomebaseApp.Middleware.adminRequired] do
  let ctx ← getCtx
  let users := getUsers ctx
  html (Shared.render ctx "Admin - Users" "/admin" (userListContent ctx users))

-- View user
view adminUser "/admin/user/:id" [HomebaseApp.Middleware.authRequired, HomebaseApp.Middleware.adminRequired] (id : Nat) do
  let ctx ← getCtx
  match getUser ctx id with
  | some user =>
    html (Shared.render ctx s!"User: {user.name}" "/admin" (userDetailContent ctx id user))
  | none => notFound "User not found"

-- Create user form
view adminCreateUser "/admin/user/new" [HomebaseApp.Middleware.authRequired, HomebaseApp.Middleware.adminRequired] do
  let ctx ← getCtx
  html (Shared.render ctx "Create User" "/admin" (createUserContent ctx))

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
    html (Shared.render ctx s!"Edit User: {user.name}" "/admin" (editUserContent ctx id user))
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
