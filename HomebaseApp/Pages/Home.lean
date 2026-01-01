/-
  HomebaseApp.Pages.Home - Home page (unified route + logic + view)
-/
import Loom
import Loom.Stencil
import HomebaseApp.Shared

namespace HomebaseApp.Pages

open Loom
open Loom.Page
open Loom.ActionM
open HomebaseApp.Shared

/-! ## Home Page Definition -/

page home "/" GET do
  let ctx ← getCtx
  if !isLoggedIn ctx then
    return ← redirect "/login"
  -- Use Stencil template instead of Scribe
  Loom.Stencil.ActionM.render "home"

end HomebaseApp.Pages
