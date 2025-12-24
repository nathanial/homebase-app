/-
  HomebaseApp.Views.Chat - Chat section view
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.Chat

open Scribe
open Loom
open HomebaseApp.Views.Layout

def content : HtmlM Unit := do
  div [class_ "section-placeholder"] do
    h1 [] (text "Chat")
    p [] (text "Chat section coming soon.")

def render (ctx : Context) : String :=
  Layout.render ctx "Chat - Homebase" "/chat" content

end HomebaseApp.Views.Chat
