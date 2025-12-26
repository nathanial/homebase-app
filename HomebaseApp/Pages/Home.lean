/-
  HomebaseApp.Pages.Home - Home page (unified route + logic + view)
-/
import Scribe
import Loom
import HomebaseApp.Shared

namespace HomebaseApp.Pages

open Scribe
open Loom
open Loom.Page
open Loom.ActionM
open HomebaseApp.Shared

/-! ## Home Page Content -/

/-- Home page content -/
def homeContent : HtmlM Unit := do
  div [class_ "bg-white rounded-xl shadow-sm p-8"] do
    h1 [class_ "text-3xl font-bold text-slate-800 mb-4"] (text "Welcome to Homebase")
    p [class_ "text-slate-600 mb-6"] do
      text "Your personal dashboard built with "
      span [class_ "font-semibold text-slate-800"] (text "Lean 4")
      text " and "
      span [class_ "font-semibold text-slate-800"] (text "Loom")
      text "."
    p [class_ "text-slate-600"] (text "Select a section from the sidebar to get started.")

/-! ## Home Page Definition -/

page home "/" GET do
  let ctx ← getCtx
  if !isLoggedIn ctx then
    return ← redirect "/login"
  html (Shared.render ctx "Homebase" "/" homeContent)

end HomebaseApp.Pages
