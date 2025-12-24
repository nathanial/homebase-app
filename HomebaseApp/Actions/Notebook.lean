/-
  HomebaseApp.Actions.Notebook - Notebook section action
-/
import Loom
import HomebaseApp.Helpers
import HomebaseApp.Views.Notebook

namespace HomebaseApp.Actions.Notebook

open Loom
open HomebaseApp.Helpers

def index : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := HomebaseApp.Views.Notebook.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Notebook
