/-
  HomebaseApp.Actions.Health - Crohn's Disease section action
-/
import Loom
import HomebaseApp.Views.Health

namespace HomebaseApp.Actions.Health

open Loom

def index : Action := fun ctx => do
  let html := HomebaseApp.Views.Health.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Health
