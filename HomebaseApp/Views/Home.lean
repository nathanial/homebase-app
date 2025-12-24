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

/-- Home page content (polymorphic) -/
def homeContent : HtmlM .stable .toplevel Unit := do
  div [class_ "bg-white rounded-xl shadow-sm p-8"] do
    h1 [class_ "text-3xl font-bold text-slate-800 mb-4"] (text "Welcome to Homebase")
    p [class_ "text-slate-600 mb-6"] do
      text "Your personal dashboard built with "
      span [class_ "font-semibold text-slate-800"] (text "Lean 4")
      text " and "
      span [class_ "font-semibold text-slate-800"] (text "Loom")
      text "."
    p [class_ "text-slate-600"] (text "Select a section from the sidebar to get started.")

/-- Render home page -/
def render (ctx : Context) : String :=
  Layout.render ctx "Homebase" "/" homeContent

end HomebaseApp.Views.Home
