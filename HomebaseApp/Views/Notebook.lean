/-
  HomebaseApp.Views.Notebook - Notebook section view
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.Notebook

open Scribe
open Loom
open HomebaseApp.Views.Layout

def content : HtmlM Unit := do
  div [class_ "section-placeholder"] do
    h1 [] (text "Notebook")
    p [] (text "Notebook section coming soon.")

def render (ctx : Context) : String :=
  Layout.render ctx "Notebook - Homebase" "/notebook" content

end HomebaseApp.Views.Notebook
