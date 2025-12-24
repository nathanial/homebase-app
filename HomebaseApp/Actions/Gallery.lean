/-
  HomebaseApp.Actions.Gallery - Gallery section action
-/
import Loom
import HomebaseApp.Views.Gallery

namespace HomebaseApp.Actions.Gallery

open Loom

def index : Action := fun ctx => do
  let html := HomebaseApp.Views.Gallery.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Gallery
