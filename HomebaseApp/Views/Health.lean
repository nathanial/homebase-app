/-
  HomebaseApp.Views.Health - Crohn's Disease section view
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.Health

open Scribe
open Loom
open HomebaseApp.Views.Layout

def content : HtmlM Unit := do
  div [class_ "section-placeholder"] do
    h1 [] (text "Crohn's Disease")
    p [] (text "Health tracking section coming soon.")

def render (ctx : Context) : String :=
  Layout.render ctx "Crohn's Disease - Homebase" "/health" content

end HomebaseApp.Views.Health
