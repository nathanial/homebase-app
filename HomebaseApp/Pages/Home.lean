/-
  HomebaseApp.Pages.Home - Home page
-/
import Loom
import Loom.Stencil
import HomebaseApp.Shared
import HomebaseApp.StencilHelpers

namespace HomebaseApp.Pages

open Loom
open Loom.Page
open Loom.ActionM
open HomebaseApp.Shared (isLoggedIn)
open HomebaseApp.StencilHelpers

page home "/" GET do
  let ctx ← getCtx
  if !isLoggedIn ctx then
    return ← redirect "/login"
  let data := pageContext ctx "Home" PageId.home
  Loom.Stencil.ActionM.renderWithLayout "app" "home" data

end HomebaseApp.Pages
