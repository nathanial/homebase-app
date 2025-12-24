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

def content : HtmlM .stable Unit := do
  div [class_ "bg-white rounded-xl shadow-sm p-8 text-center"] do
    div [class_ "text-6xl mb-4"] (text "🖼️")
    h1 [class_ "text-2xl font-bold text-slate-800 mb-2"] (text "Gallery")
    p [class_ "text-slate-500"] (text "Gallery section coming soon.")

def render (ctx : Context) : String :=
  Layout.render ctx "Gallery - Homebase" "/gallery" content

end HomebaseApp.Views.Gallery
