/-
  HomebaseApp.Actions.Kanban - Kanban section action
-/
import Loom
import HomebaseApp.Views.Kanban

namespace HomebaseApp.Actions.Kanban

open Loom

def index : Action := fun ctx => do
  let html := HomebaseApp.Views.Kanban.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Kanban
