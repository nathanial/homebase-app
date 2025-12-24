/-
  HomebaseApp.Actions.Home - Home page action
-/
import Loom
import HomebaseApp.Helpers
import HomebaseApp.Views.Home

namespace HomebaseApp.Actions.Home

open Loom
open HomebaseApp.Helpers

def index : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := HomebaseApp.Views.Home.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Home
