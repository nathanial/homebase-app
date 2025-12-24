/-
  HomebaseApp.Actions.Recipes - Recipes section action
-/
import Loom
import HomebaseApp.Views.Recipes

namespace HomebaseApp.Actions.Recipes

open Loom

def index : Action := fun ctx => do
  let html := HomebaseApp.Views.Recipes.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Recipes
