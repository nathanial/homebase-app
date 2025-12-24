/-
  HomebaseApp.Actions.News - News section action
-/
import Loom
import HomebaseApp.Helpers
import HomebaseApp.Views.News

namespace HomebaseApp.Actions.News

open Loom
open HomebaseApp.Helpers

def index : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := HomebaseApp.Views.News.render ctx
  Action.html html ctx

end HomebaseApp.Actions.News
