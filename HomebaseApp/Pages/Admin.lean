/-
  HomebaseApp.Pages.Admin - Admin panel for user management
-/
import Scribe
import Loom
import Ledger
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Helpers

namespace HomebaseApp.Pages

open Scribe
open Loom
open Loom.Page
open Loom.ActionM
open Ledger
open HomebaseApp.Shared hiding isLoggedIn isAdmin
open HomebaseApp.Models
open HomebaseApp.Helpers hiding isLoggedIn isAdmin hashPassword

def adminIsLoggedIn (ctx : Context) : Bool :=
  ctx.session.has "user_id"

def adminCurrentUserId (ctx : Context) : Option String :=
  ctx.session.get "user_id"

def adminIsAdmin (ctx : Context) : Bool :=
  match adminCurrentUserId ctx with
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

private def polyHash (data : ByteArray) : Nat :=
  let prime : Nat := 31
  data.foldl (init := 0) fun hash byte =>
    hash * prime + byte.toNat

private def toHexString (n : Nat) : String :=
  let hex := n.toDigits 16
  String.mk hex

def adminHashPassword (password : String) (secret : ByteArray) : String :=
  let passBytes := password.toUTF8
  let combined := secret ++ passBytes
  let hash1 := polyHash combined
  let hash1Str := toString hash1
  let hash2 := polyHash (combined ++ hash1Str.toUTF8)
  s!"{toHexString hash1}-{toHexString hash2}"

def adminFindUserByEmail (ctx : Context) (email : String) : Option EntityId :=
  ctx.database.bind fun db =>
    db.findOneByAttrValue userEmail (.string email)

def adminGetAllUsers (ctx : Context) : List (EntityId × String × String × Bool) :=
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

def adminGetAttrString (ctx : Context) (entityId : EntityId) (attr : Attribute) : Option String :=
  ctx.database.bind fun db =>
    match db.getOne entityId attr with
    | some (.string s) => some s
    | _ => none

def adminGetAttrBool (ctx : Context) (entityId : EntityId) (attr : Attribute) : Option Bool :=
  ctx.database.bind fun db =>
    match db.getOne entityId attr with
    | some (.bool b) => some b
    | _ => none

def userListContent (ctx : Context) (users : List (EntityId × String × String × Bool)) : HtmlM Unit := do
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
          for (eid, email, name, isAdminVal) in users do
            tr [] do
              td [] (text (toString eid.id))
              td [] (text name)
              td [] (text email)
              td [] do
                if isAdminVal then
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

def userDetailContent (ctx : Context) (userId : Nat) (email name : String) (isAdminVal : Bool) : HtmlM Unit := do
  div [class_ "admin-container"] do
    div [class_ "admin-header"] do
      h1 [class_ "admin-title"] (text s!"User: {name}")
      div [class_ "admin-actions"] do
        a [href_ s!"/admin/user/{userId}/edit", class_ "btn btn-primary"] (text "Edit")
        a [href_ "/admin", class_ "btn btn-secondary"] (text "Back to List")
    div [class_ "card"] do
      dl [class_ "detail-list"] do
        dt [] (text "ID")
        dd [] (text (toString userId))
        dt [] (text "Name")
        dd [] (text name)
        dt [] (text "Email")
        dd [] (text email)
        dt [] (text "Admin")
        dd [] do
          if isAdminVal then
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

def editUserContent (ctx : Context) (userId : Nat) (email name : String) (isAdminVal : Bool) : HtmlM Unit := do
  div [class_ "admin-container"] do
    div [class_ "admin-header"] do
      h1 [class_ "admin-title"] (text s!"Edit User: {name}")
      a [href_ "/admin", class_ "btn btn-secondary"] (text "Back to List")
    div [class_ "card"] do
      form [method_ "POST", action_ s!"/admin/user/{userId}"] do
        input [type_ "hidden", name_ "_method", value_ "PUT"]
        csrfField ctx.csrfToken
        div [class_ "form-stack"] do
          div [class_ "form-group"] do
            label [for_ "name", class_ "form-label"] (text "Name")
            input [type_ "text", name_ "name", id_ "name", value_ name,
                   class_ "form-input", required_]
          div [class_ "form-group"] do
            label [for_ "email", class_ "form-label"] (text "Email")
            input [type_ "email", name_ "email", id_ "email", value_ email,
                   class_ "form-input", required_]
          div [class_ "form-group"] do
            label [for_ "password", class_ "form-label"] (text "Password (leave blank to keep current)")
            input [type_ "password", name_ "password", id_ "password",
                   class_ "form-input",
                   placeholder_ "Leave blank to keep current password"]
          div [class_ "form-group form-checkbox"] do
            if isAdminVal then
              input [type_ "checkbox", name_ "is_admin", id_ "is_admin", checked_]
            else
              input [type_ "checkbox", name_ "is_admin", id_ "is_admin"]
            label [for_ "is_admin", class_ "form-label"] (text "Admin privileges")
          div [class_ "form-actions"] do
            button [type_ "submit", class_ "btn btn-primary"] (text "Save Changes")
            a [href_ "/admin", class_ "btn btn-secondary"] (text "Cancel")

page admin "/admin" GET do
  let ctx ← getCtx
  if !adminIsLoggedIn ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Please log in to continue"
    return ← redirect "/login"
  if !adminIsAdmin ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Access denied. Admin privileges required."
    return ← redirect "/"
  let users := adminGetAllUsers ctx
  html (Shared.render ctx "Admin - Users" "/admin" (userListContent ctx users))

page adminUser "/admin/user/:id" GET (id : Nat) do
  let ctx ← getCtx
  if !adminIsLoggedIn ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Please log in to continue"
    return ← redirect "/login"
  if !adminIsAdmin ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Access denied. Admin privileges required."
    return ← redirect "/"
  let eid : EntityId := ⟨id⟩
  match adminGetAttrString ctx eid userEmail, adminGetAttrString ctx eid userName with
  | some email, some name =>
    let isAdminVal := match adminGetAttrBool ctx eid userIsAdmin with
      | some b => b
      | none => false
    html (Shared.render ctx s!"User: {name}" "/admin" (userDetailContent ctx id email name isAdminVal))
  | _, _ => notFound "User not found"

page adminCreateUser "/admin/user/new" GET do
  let ctx ← getCtx
  if !adminIsLoggedIn ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Please log in to continue"
    return ← redirect "/login"
  if !adminIsAdmin ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Access denied. Admin privileges required."
    return ← redirect "/"
  html (Shared.render ctx "Create User" "/admin" (createUserContent ctx))

page adminStoreUser "/admin/user" POST do
  let ctx ← getCtx
  if !adminIsLoggedIn ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Please log in to continue"
    return ← redirect "/login"
  if !adminIsAdmin ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Access denied. Admin privileges required."
    return ← redirect "/"
  let name := ctx.paramD "name" ""
  let email := ctx.paramD "email" ""
  let password := ctx.paramD "password" ""
  let isAdminParam := ctx.paramD "is_admin" ""
  if name.isEmpty || email.isEmpty || password.isEmpty then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Name, email, and password are required"
    return ← redirect "/admin/user/new"
  match adminFindUserByEmail ctx email with
  | some _ =>
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Email already registered"
    redirect "/admin/user/new"
  | none =>
    match ← allocEntityId with
    | none =>
      modifyCtx fun c => c.withFlash fun f => f.set "error" "Database not available"
      redirect "/admin"
    | some userId =>
      let ctx ← getCtx
      let passwordHash := adminHashPassword password ctx.config.secretKey
      let isAdminVal := isAdminParam == "on" || isAdminParam == "true"
      let tx : Transaction := [
        .add userId userName (.string name),
        .add userId userEmail (.string email),
        .add userId userPasswordHash (.string passwordHash),
        .add userId userIsAdmin (.bool isAdminVal)
      ]
      match ← transact tx with
      | .ok () =>
        modifyCtx fun c => c.withFlash fun f => f.set "success" s!"User '{name}' created successfully"
        redirect "/admin"
      | .error e =>
        modifyCtx fun c => c.withFlash fun f => f.set "error" s!"Failed to create user: {e}"
        redirect "/admin/user/new"

page adminEditUser "/admin/user/:id/edit" GET (id : Nat) do
  let ctx ← getCtx
  if !adminIsLoggedIn ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Please log in to continue"
    return ← redirect "/login"
  if !adminIsAdmin ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Access denied. Admin privileges required."
    return ← redirect "/"
  let eid : EntityId := ⟨id⟩
  match adminGetAttrString ctx eid userEmail, adminGetAttrString ctx eid userName with
  | some email, some name =>
    let isAdminVal := match adminGetAttrBool ctx eid userIsAdmin with
      | some b => b
      | none => false
    html (Shared.render ctx s!"Edit User: {name}" "/admin" (editUserContent ctx id email name isAdminVal))
  | _, _ => notFound "User not found"

page adminUpdateUser "/admin/user/:id" PUT (id : Nat) do
  let ctx ← getCtx
  if !adminIsLoggedIn ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Please log in to continue"
    return ← redirect "/login"
  if !adminIsAdmin ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Access denied. Admin privileges required."
    return ← redirect "/"
  let name := ctx.paramD "name" ""
  let email := ctx.paramD "email" ""
  let password := ctx.paramD "password" ""
  let isAdminParam := ctx.paramD "is_admin" ""
  if name.isEmpty || email.isEmpty then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Name and email are required"
    return ← redirect s!"/admin/user/{id}/edit"
  let eid : EntityId := ⟨id⟩
  match adminFindUserByEmail ctx email with
  | some existingId =>
    if existingId.id.toNat != id then
      modifyCtx fun c => c.withFlash fun f => f.set "error" "Email already taken by another user"
      return ← redirect s!"/admin/user/{id}/edit"
    else
      pure ()
  | none => pure ()
  match ctx.database with
  | none =>
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Database not available"
    redirect "/admin"
  | some db =>
    let isAdminVal := isAdminParam == "on" || isAdminParam == "true"
    let mut tx : Transaction := []
    match db.getOne eid userName with
    | some oldVal => tx := tx ++ [.retract eid userName oldVal]
    | none => pure ()
    tx := tx ++ [.add eid userName (.string name)]
    match db.getOne eid userEmail with
    | some oldVal => tx := tx ++ [.retract eid userEmail oldVal]
    | none => pure ()
    tx := tx ++ [.add eid userEmail (.string email)]
    match db.getOne eid userIsAdmin with
    | some oldVal => tx := tx ++ [.retract eid userIsAdmin oldVal]
    | none => pure ()
    tx := tx ++ [.add eid userIsAdmin (.bool isAdminVal)]
    if !password.isEmpty then
      let passwordHash := adminHashPassword password ctx.config.secretKey
      match db.getOne eid userPasswordHash with
      | some oldVal => tx := tx ++ [.retract eid userPasswordHash oldVal]
      | none => pure ()
      tx := tx ++ [.add eid userPasswordHash (.string passwordHash)]
    match ← transact tx with
    | .ok () =>
      modifyCtx fun c => c.withFlash fun f => f.set "success" s!"User '{name}' updated successfully"
      redirect "/admin"
    | .error e =>
      modifyCtx fun c => c.withFlash fun f => f.set "error" s!"Failed to update user: {e}"
      redirect s!"/admin/user/{id}/edit"

page adminDeleteUser "/admin/user/:id" DELETE (id : Nat) do
  let ctx ← getCtx
  if !adminIsLoggedIn ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Please log in to continue"
    return ← redirect "/login"
  if !adminIsAdmin ctx then
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Access denied. Admin privileges required."
    return ← redirect "/"
  match adminCurrentUserId ctx with
  | some currentId =>
    if currentId == toString id then
      modifyCtx fun c => c.withFlash fun f => f.set "error" "You cannot delete your own account"
      return ← redirect "/admin"
    else
      pure ()
  | none => pure ()
  let eid : EntityId := ⟨id⟩
  match ctx.database with
  | none =>
    modifyCtx fun c => c.withFlash fun f => f.set "error" "Database not available"
    redirect "/admin"
  | some db =>
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
    match ← transact tx with
    | .ok () =>
      modifyCtx fun c => c.withFlash fun f => f.set "success" "User deleted successfully"
      redirect "/admin"
    | .error e =>
      modifyCtx fun c => c.withFlash fun f => f.set "error" s!"Failed to delete user: {e}"
      redirect "/admin"

end HomebaseApp.Pages
