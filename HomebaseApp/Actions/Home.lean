/-
  HomebaseApp.Actions.Home - Home page action
-/
import Loom
import HomebaseApp.Views.Home

namespace HomebaseApp.Actions.Home

open Loom

def index : Action := fun ctx => do
  let html := HomebaseApp.Views.Home.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Home
