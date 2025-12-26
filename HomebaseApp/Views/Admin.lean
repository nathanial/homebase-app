/-
  HomebaseApp.Views.Admin - Admin panel views for user management
-/
import Scribe
import Loom
import Ledger
import HomebaseApp.Views.Layout
import HomebaseApp.Routes

namespace HomebaseApp.Views.Admin

open Scribe
open Loom
open Ledger
open HomebaseApp.Views.Layout
open HomebaseApp (Route)

/-- User list content -/
def userListContent (ctx : Context) (users : List (EntityId × String × String × Bool)) : HtmlM Unit := do
  div [class_ "admin-container"] do
    -- Header
    div [class_ "admin-header"] do
      h1 [class_ "admin-title"] (text "User Management")
      a [href' Route.adminCreateUser, class_ "btn btn-primary"] (text "+ Add User")

    -- User table
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
                a [href' (Route.adminUser eid.id.toNat), class_ "btn btn-sm btn-secondary"]
                  (text "View")
                a [href' (Route.adminEditUser eid.id.toNat), class_ "btn btn-sm btn-primary"]
                  (text "Edit")
                button [class_ "btn btn-sm btn-danger",
                        hx_delete' (Route.adminDeleteUser eid.id.toNat),
                        attr_ "hx-confirm" "Are you sure you want to delete this user?",
                        attr_ "hx-target" "body"]
                  (text "Delete")

/-- Render user list page -/
def renderUserList (ctx : Context) (users : List (EntityId × String × String × Bool)) : String :=
  Layout.render ctx "Admin - Users" "/admin" (userListContent ctx users)

/-- User detail content -/
def userDetailContent (ctx : Context) (userId : Nat) (email name : String) (isAdminVal : Bool) : HtmlM Unit := do
  div [class_ "admin-container"] do
    div [class_ "admin-header"] do
      h1 [class_ "admin-title"] (text s!"User: {name}")
      div [class_ "admin-actions"] do
        a [href' (Route.adminEditUser userId), class_ "btn btn-primary"] (text "Edit")
        a [href' Route.admin, class_ "btn btn-secondary"] (text "Back to List")

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

/-- Render user detail page -/
def renderUserDetail (ctx : Context) (userId : Nat) (email name : String) (isAdminVal : Bool) : String :=
  Layout.render ctx s!"User: {name}" "/admin" (userDetailContent ctx userId email name isAdminVal)

/-- Create user form content -/
def createUserContent (ctx : Context) : HtmlM Unit := do
  div [class_ "admin-container"] do
    div [class_ "admin-header"] do
      h1 [class_ "admin-title"] (text "Create User")
      a [href' Route.admin, class_ "btn btn-secondary"] (text "Back to List")

    div [class_ "card"] do
      form [method_ "POST", action' Route.adminStoreUser] do
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
            a [href' Route.admin, class_ "btn btn-secondary"] (text "Cancel")

/-- Render create user form -/
def renderCreateUserForm (ctx : Context) : String :=
  Layout.render ctx "Create User" "/admin" (createUserContent ctx)

/-- Edit user form content -/
def editUserContent (ctx : Context) (userId : Nat) (email name : String) (isAdminVal : Bool) : HtmlM Unit := do
  div [class_ "admin-container"] do
    div [class_ "admin-header"] do
      h1 [class_ "admin-title"] (text s!"Edit User: {name}")
      a [href' Route.admin, class_ "btn btn-secondary"] (text "Back to List")

    div [class_ "card"] do
      form [method_ "POST", action' (Route.adminUpdateUser userId)] do
        -- Method override for PUT
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
            a [href' Route.admin, class_ "btn btn-secondary"] (text "Cancel")

/-- Render edit user form -/
def renderEditUserForm (ctx : Context) (userId : Nat) (email name : String) (isAdminVal : Bool) : String :=
  Layout.render ctx s!"Edit User: {name}" "/admin" (editUserContent ctx userId email name isAdminVal)

end HomebaseApp.Views.Admin
