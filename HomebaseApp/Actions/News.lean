/-
  HomebaseApp.Actions.News - News section action
-/
import Loom
import HomebaseApp.Views.News

namespace HomebaseApp.Actions.News

open Loom

def index : Action := fun ctx => do
  let html := HomebaseApp.Views.News.render ctx
  Action.html html ctx

end HomebaseApp.Actions.News
