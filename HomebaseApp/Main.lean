/-
  HomebaseApp.Main - Application setup and entry point
-/
import Loom
import HomebaseApp.Helpers
import HomebaseApp.Actions.Home
import HomebaseApp.Actions.Auth
import HomebaseApp.Actions.Chat
import HomebaseApp.Actions.Notebook
import HomebaseApp.Actions.Time
import HomebaseApp.Actions.Health
import HomebaseApp.Actions.Recipes
import HomebaseApp.Actions.Kanban
import HomebaseApp.Actions.Gallery
import HomebaseApp.Actions.News

namespace HomebaseApp

open Loom
open HomebaseApp.Helpers

/-- Application configuration -/
def config : AppConfig := {
  secretKey := "homebase-app-secret-key-min-32-chars!!".toUTF8
  sessionCookieName := "homebase_session"
  csrfFieldName := "_csrf"
  csrfEnabled := false
}

/-- Path to the JSONL journal file for persistence -/
def journalPath : System.FilePath := "data/homebase.jsonl"

/-- Wrapper to extract :id parameter and pass to action -/
def withId (f : Nat → Action) : Action := fun ctx => do
  match ctx.params.get "id" with
  | none => Action.badRequest ctx "Missing ID parameter"
  | some idStr =>
    match idStr.toNat? with
    | none => Action.badRequest ctx "Invalid ID parameter"
    | some id => f id ctx

/-- Build the application with all routes using persistent database -/
def buildApp : App :=
  Loom.app config
    -- Middleware
    |>.use Middleware.logging
    |>.use Middleware.securityHeaders
    -- Public routes
    |>.get "/" "home" Actions.Home.index
    |>.get "/login" "login_form" Actions.Auth.loginForm
    |>.post "/login" "login" Actions.Auth.login
    |>.get "/register" "register_form" Actions.Auth.registerForm
    |>.post "/register" "register" Actions.Auth.register
    |>.get "/logout" "logout" Actions.Auth.logout
    -- Section routes
    |>.get "/chat" "chat" Actions.Chat.index
    |>.get "/notebook" "notebook" Actions.Notebook.index
    |>.get "/time" "time" Actions.Time.index
    |>.get "/health" "health" Actions.Health.index
    |>.get "/recipes" "recipes" Actions.Recipes.index
    |>.get "/gallery" "gallery" Actions.Gallery.index
    |>.get "/news" "news" Actions.News.index
    -- Kanban routes
    |>.get "/kanban" "kanban" Actions.Kanban.index
    -- Kanban column routes
    |>.get "/kanban/add-column-form" "kanban_add_column_form" Actions.Kanban.addColumnForm
    |>.get "/kanban/add-column-button" "kanban_add_column_button" Actions.Kanban.addColumnButton
    |>.post "/kanban/column" "kanban_create_column" Actions.Kanban.createColumn
    |>.get "/kanban/column/:id" "kanban_get_column" (withId Actions.Kanban.getColumnPartial)
    |>.get "/kanban/column/:id/edit" "kanban_edit_column_form" (withId Actions.Kanban.editColumnForm)
    |>.put "/kanban/column/:id" "kanban_update_column" (withId Actions.Kanban.updateColumn)
    |>.delete "/kanban/column/:id" "kanban_delete_column" (withId Actions.Kanban.deleteColumn)
    |>.get "/kanban/column/:id/add-card-form" "kanban_add_card_form" (withId Actions.Kanban.addCardForm)
    |>.get "/kanban/column/:id/add-card-button" "kanban_add_card_button" (withId Actions.Kanban.addCardButton)
    -- Kanban card routes
    |>.post "/kanban/card" "kanban_create_card" Actions.Kanban.createCard
    |>.get "/kanban/card/:id" "kanban_get_card" (withId Actions.Kanban.getCardPartial)
    |>.get "/kanban/card/:id/edit" "kanban_edit_card_form" (withId Actions.Kanban.editCardForm)
    |>.put "/kanban/card/:id" "kanban_update_card" (withId Actions.Kanban.updateCard)
    |>.delete "/kanban/card/:id" "kanban_delete_card" (withId Actions.Kanban.deleteCard)
    |>.post "/kanban/card/:id/move" "kanban_move_card" (withId Actions.Kanban.moveCard)
    |>.post "/kanban/card/:id/reorder" "kanban_reorder_card" (withId Actions.Kanban.reorderCard)
    -- Persistent database (auto-persists to JSONL)
    |>.withPersistentDatabase journalPath

/-- Main entry point (inside namespace) -/
def runApp : IO Unit := do
  IO.FS.createDirAll "data"
  IO.println "Starting Homebase App..."
  IO.println s!"Database: Persistent (journal at {journalPath})"
  let app := buildApp
  app.run "0.0.0.0" 3000

end HomebaseApp

/-- Top-level main entry point for executable -/
def main : IO Unit := HomebaseApp.runApp
