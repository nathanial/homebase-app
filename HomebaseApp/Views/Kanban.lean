/-
  HomebaseApp.Views.Kanban - Kanban section view
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.Kanban

open Scribe
open Loom
open HomebaseApp.Views.Layout

def content : HtmlM Unit := do
  div [class_ "section-placeholder"] do
    h1 [] (text "Kanban")
    p [] (text "Kanban board section coming soon.")

def render (ctx : Context) : String :=
  Layout.render ctx "Kanban - Homebase" "/kanban" content

end HomebaseApp.Views.Kanban
