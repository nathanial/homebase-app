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
  div [class_ "bg-white rounded-xl shadow-sm p-8 text-center"] do
    div [class_ "text-6xl mb-4"] (text "📋")
    h1 [class_ "text-2xl font-bold text-slate-800 mb-2"] (text "Kanban")
    p [class_ "text-slate-500"] (text "Kanban board section coming soon.")

def render (ctx : Context) : String :=
  Layout.render ctx "Kanban - Homebase" "/kanban" content

end HomebaseApp.Views.Kanban
