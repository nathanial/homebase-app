/-
  HomebaseApp.Actions.Chat - Chat section action
-/
import Loom
import HomebaseApp.Helpers
import HomebaseApp.Views.Chat

namespace HomebaseApp.Actions.Chat

open Loom
open HomebaseApp.Helpers

def index : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := HomebaseApp.Views.Chat.render ctx
  Action.html html ctx

end HomebaseApp.Actions.Chat
