/-
  HomebaseApp.Actions.Gallery - Gallery section action
-/
import Loom
import HomebaseApp.Helpers
import HomebaseApp.Views.Gallery

namespace HomebaseApp.Actions.Gallery

open Loom
open HomebaseApp.Helpers

def index : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := HomebaseApp.Views.Gallery.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Gallery
