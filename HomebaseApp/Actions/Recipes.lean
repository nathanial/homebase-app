/-
  HomebaseApp.Actions.Recipes - Recipes section action
-/
import Loom
import HomebaseApp.Helpers
import HomebaseApp.Views.Recipes

namespace HomebaseApp.Actions.Recipes

open Loom
open HomebaseApp.Helpers

def index : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := HomebaseApp.Views.Recipes.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Recipes
