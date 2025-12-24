/-
  HomebaseApp.Views.News - News section view
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.News

open Scribe
open Loom
open HomebaseApp.Views.Layout

def content : HtmlM Unit := do
  div [class_ "section-placeholder"] do
    h1 [] (text "News")
    p [] (text "News section coming soon.")

def render (ctx : Context) : String :=
  Layout.render ctx "News - Homebase" "/news" content

end HomebaseApp.Views.News
