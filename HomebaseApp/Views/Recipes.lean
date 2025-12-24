/-
  HomebaseApp.Views.Recipes - Recipes section view
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.Recipes

open Scribe
open Loom
open HomebaseApp.Views.Layout

def content : HtmlM Unit := do
  div [class_ "section-placeholder"] do
    h1 [] (text "Recipes")
    p [] (text "Recipes section coming soon.")

def render (ctx : Context) : String :=
  Layout.render ctx "Recipes - Homebase" "/recipes" content

end HomebaseApp.Views.Recipes
