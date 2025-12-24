/-
  HomebaseApp.Views.Home - Home page view
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.Home

open Scribe
open Loom
open HomebaseApp.Views.Layout

/-- Home page content -/
def homeContent (ctx : Context) : HtmlM Unit := do
  div [class_ "card"] do
    h1 [] (text "Welcome to Homebase")
    p [] do
      text "Your personal dashboard built with "
      strong [] (text "Lean 4")
      text " and "
      strong [] (text "Loom")
      text "."
    div [class_ "mt-2"] do
      match ctx.session.get "user_id" with
      | some _ =>
        p [] (text "Select a section from the sidebar to get started.")
      | none =>
        p [] (text "Get started by creating an account or logging in.")
        div [class_ "mt-2"] do
          a [href_ "/register", class_ "btn"] (text "Register")
          text " "
          a [href_ "/login", class_ "btn btn-secondary"] (text "Login")

/-- Render home page -/
def render (ctx : Context) : String :=
  Layout.render ctx "Homebase" "/" (homeContent ctx)

end HomebaseApp.Views.Home
