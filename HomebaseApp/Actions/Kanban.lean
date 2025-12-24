/-
  HomebaseApp.Actions.Kanban - Kanban section action
-/
import Loom
import HomebaseApp.Helpers
import HomebaseApp.Views.Kanban

namespace HomebaseApp.Actions.Kanban

open Loom
open HomebaseApp.Helpers

def index : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := HomebaseApp.Views.Kanban.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Kanban
