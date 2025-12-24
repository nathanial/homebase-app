/-
  HomebaseApp.Actions.Time - Time section action
-/
import Loom
import HomebaseApp.Helpers
import HomebaseApp.Views.Time

namespace HomebaseApp.Actions.Time

open Loom
open HomebaseApp.Helpers

def index : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := HomebaseApp.Views.Time.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Time
