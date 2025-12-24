/-
  HomebaseApp.Actions.Health - Crohn's Disease section action
-/
import Loom
import HomebaseApp.Helpers
import HomebaseApp.Views.Health

namespace HomebaseApp.Actions.Health

open Loom
open HomebaseApp.Helpers

def index : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := HomebaseApp.Views.Health.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Health
