/-
  HomebaseApp.Views.Auth - Authentication views (login, register)
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.Auth

open Scribe
open Loom
open HomebaseApp.Views.Layout

/-- Login form content -/
def loginContent (ctx : Context) : HtmlM Unit := do
  div [class_ "card"] do
    h1 [] (text "Login")
    form [method_ "post", action_ "/login"] do
      csrfField ctx.csrfToken
      div [] do
        label [for_ "email"] (text "Email")
        input [type_ "email", name_ "email", id_ "email", required_, placeholder_ "you@example.com"]
      div [] do
        label [for_ "password"] (text "Password")
        input [type_ "password", name_ "password", id_ "password", required_, placeholder_ "Your password"]
      button [type_ "submit"] (text "Login")
    p [class_ "mt-2 text-muted"] do
      text "Don't have an account? "
      a [href_ "/register"] (text "Register here")

/-- Render login page -/
def renderLogin (ctx : Context) : String :=
  Layout.renderSimple ctx "Login - Homebase" (loginContent ctx)

/-- Register form content -/
def registerContent (ctx : Context) : HtmlM Unit := do
  div [class_ "card"] do
    h1 [] (text "Create Account")
    form [method_ "post", action_ "/register"] do
      csrfField ctx.csrfToken
      div [] do
        label [for_ "name"] (text "Name")
        input [type_ "text", name_ "name", id_ "name", required_, placeholder_ "Your name"]
      div [] do
        label [for_ "email"] (text "Email")
        input [type_ "email", name_ "email", id_ "email", required_, placeholder_ "you@example.com"]
      div [] do
        label [for_ "password"] (text "Password")
        input [type_ "password", name_ "password", id_ "password", required_, placeholder_ "Choose a password"]
      button [type_ "submit"] (text "Create Account")
    p [class_ "mt-2 text-muted"] do
      text "Already have an account? "
      a [href_ "/login"] (text "Login here")

/-- Render register page -/
def renderRegister (ctx : Context) : String :=
  Layout.renderSimple ctx "Register - Homebase" (registerContent ctx)

end HomebaseApp.Views.Auth
