/-
  HomebaseApp.Actions.Notebook - Notebook section action
-/
import Loom
import HomebaseApp.Views.Notebook

namespace HomebaseApp.Actions.Notebook

open Loom

def index : Action := fun ctx => do
  let html := HomebaseApp.Views.Notebook.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Notebook
