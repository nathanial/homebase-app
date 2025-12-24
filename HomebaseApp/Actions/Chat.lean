/-
  HomebaseApp.Actions.Chat - Chat section action
-/
import Loom
import HomebaseApp.Views.Chat

namespace HomebaseApp.Actions.Chat

open Loom

def index : Action := fun ctx => do
  let html := HomebaseApp.Views.Chat.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Chat
