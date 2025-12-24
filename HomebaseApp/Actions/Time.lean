/-
  HomebaseApp.Actions.Time - Time section action
-/
import Loom
import HomebaseApp.Views.Time

namespace HomebaseApp.Actions.Time

open Loom

def index : Action := fun ctx => do
  let html := HomebaseApp.Views.Time.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Time
