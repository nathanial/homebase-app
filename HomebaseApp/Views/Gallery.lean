/-
  HomebaseApp.Views.Gallery - Gallery section view
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.Gallery

open Scribe
open Loom
open HomebaseApp.Views.Layout

def content : HtmlM Unit := do
  div [class_ "section-placeholder"] do
    h1 [] (text "Gallery")
    p [] (text "Gallery section coming soon.")

def render (ctx : Context) : String :=
  Layout.render ctx "Gallery - Homebase" "/gallery" content

end HomebaseApp.Views.Gallery
