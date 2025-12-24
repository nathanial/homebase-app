/-
  HomebaseApp.Views.Time - Time section view
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.Time

open Scribe
open Loom
open HomebaseApp.Views.Layout

def content : HtmlM Unit := do
  div [class_ "section-placeholder"] do
    h1 [] (text "Time")
    p [] (text "Time tracking section coming soon.")

def render (ctx : Context) : String :=
  Layout.render ctx "Time - Homebase" "/time" content

end HomebaseApp.Views.Time
