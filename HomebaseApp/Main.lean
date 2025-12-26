/-
  HomebaseApp.Main - Application setup and entry point
-/
import Loom
import Ledger
import Chronicle
import HomebaseApp.Models
import HomebaseApp.Helpers
import HomebaseApp.Actions.Home
import HomebaseApp.Actions.Auth
import HomebaseApp.Actions.Admin
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
open Ledger
open HomebaseApp.Models
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

/-- Path to the JSON log file (structured logging) -/
def jsonLogPath : System.FilePath := "logs/homebase.json"

/-- Path to the text log file (human-readable) -/
def textLogPath : System.FilePath := "logs/homebase.log"

/-- Wrapper to extract :id parameter and pass to action -/
def withId (f : Nat → Action) : Action := fun ctx => do
  match ctx.params.get "id" with
  | none => Action.badRequest ctx "Missing ID parameter"
  | some idStr =>
    match idStr.toNat? with
    | none => Action.badRequest ctx "Invalid ID parameter"
    | some id => f id ctx

/-- Build the application with all routes using persistent database -/
def buildApp (logger : Chronicle.MultiLogger) : App :=
  Loom.app config
    -- Logger for action-level logging
    |>.withLogger logger
    -- Middleware
    |>.use Middleware.methodOverride
    |>.use (Loom.Chronicle.fileLoggingMulti logger)
    |>.use Middleware.securityHeaders
    -- SSE endpoints for real-time updates
    |>.sseEndpoint "/events/kanban" "kanban"
    |>.sseEndpoint "/events/chat" "chat"
    -- Public routes
    |>.get "/" "home" Actions.Home.index
    |>.get "/login" "login_form" Actions.Auth.loginForm
    |>.post "/login" "login" Actions.Auth.login
    |>.get "/register" "register_form" Actions.Auth.registerForm
    |>.post "/register" "register" Actions.Auth.register
    |>.get "/logout" "logout" Actions.Auth.logout
    -- Section routes
    |>.get "/notebook" "notebook" Actions.Notebook.index
    |>.get "/time" "time" Actions.Time.index
    |>.get "/health" "health" Actions.Health.index
    |>.get "/recipes" "recipes" Actions.Recipes.index
    |>.get "/gallery" "gallery" Actions.Gallery.index
    |>.get "/news" "news" Actions.News.index
    -- Kanban routes
    |>.get "/kanban" "kanban" Actions.Kanban.index
    |>.get "/kanban/columns" "kanban_columns" Actions.Kanban.columns
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
    -- Chat routes
    |>.get "/chat" "chat" Actions.Chat.index
    |>.get "/chat/new-thread-form" "chat_new_thread_form" Actions.Chat.newThreadForm
    |>.post "/chat/thread" "chat_create_thread" Actions.Chat.createThread
    |>.get "/chat/thread/:id" "chat_show_thread" (withId Actions.Chat.showThread)
    |>.get "/chat/thread/:id/edit" "chat_edit_thread_form" (withId Actions.Chat.editThreadForm)
    |>.put "/chat/thread/:id" "chat_update_thread" (withId Actions.Chat.updateThread)
    |>.delete "/chat/thread/:id" "chat_delete_thread" (withId Actions.Chat.deleteThread)
    |>.post "/chat/thread/:id/message" "chat_add_message" (withId Actions.Chat.addMessage)
    |>.get "/chat/search" "chat_search" Actions.Chat.search
    -- Admin routes
    |>.get "/admin" "admin" Actions.Admin.index
    |>.get "/admin/user/new" "admin_create_user" Actions.Admin.createUserForm
    |>.post "/admin/user" "admin_store_user" Actions.Admin.storeUser
    |>.get "/admin/user/:id" "admin_show_user" (withId Actions.Admin.showUser)
    |>.get "/admin/user/:id/edit" "admin_edit_user" (withId Actions.Admin.editUserForm)
    |>.put "/admin/user/:id" "admin_update_user" (withId Actions.Admin.updateUser)
    |>.delete "/admin/user/:id" "admin_delete_user" (withId Actions.Admin.deleteUser)
    -- Persistent database (auto-persists to JSONL)
    |>.withPersistentDatabase journalPath

/-- Check if there are any admin users. If no admins exist but users do,
    promote all users to admin. This ensures there's always an admin. -/
def ensureAdminExists : IO Unit := do
  -- Check if journal file exists
  if !(← journalPath.pathExists) then
    IO.println "No database found, skipping admin check."
    return

  -- Load the database
  let pc ← Ledger.Persist.PersistentConnection.create journalPath

  -- Get all users (entities with userEmail attribute)
  let userIds := pc.db.entitiesWithAttr userEmail

  if userIds.isEmpty then
    IO.println "No users in database, skipping admin check."
    return

  -- Check if any user has isAdmin = true
  let hasAdmin := userIds.any fun uid =>
    match pc.db.getOne uid userIsAdmin with
    | some (.bool true) => true
    | _ => false

  if hasAdmin then
    IO.println s!"Admin check: Found admin user(s) among {userIds.length} users."
    return

  -- No admins found! Promote all users to admin
  IO.println s!"WARNING: No admin users found! Promoting all {userIds.length} user(s) to admin..."

  let mut tx : Transaction := []
  for uid in userIds do
    -- Retract old isAdmin value if exists
    match pc.db.getOne uid userIsAdmin with
    | some oldVal => tx := tx ++ [.retract uid userIsAdmin oldVal]
    | none => pure ()
    -- Add isAdmin = true
    tx := tx ++ [.add uid userIsAdmin (.bool true)]

  -- Apply the transaction (auto-persists to journal)
  let result ← pc.transact tx
  match result with
  | .ok (pc', _report) =>
    -- Close the connection (flushes the journal)
    pc'.close
    IO.println s!"Successfully promoted {userIds.length} user(s) to admin."
  | .error e =>
    IO.println s!"ERROR: Failed to promote users to admin: {e}"

/-- Main entry point (inside namespace) -/
def runApp : IO Unit := do
  IO.FS.createDirAll "data"
  IO.FS.createDirAll "logs"

  -- Ensure there's at least one admin user
  ensureAdminExists

  -- Create multi-logger with both JSON and text formats
  let jsonConfig := Chronicle.Config.default jsonLogPath
    |>.withLevel .info
    |>.withFormat .json
  let textConfig := Chronicle.Config.default textLogPath
    |>.withLevel .info
    |>.withFormat .text
  let logger ← Chronicle.MultiLogger.create [jsonConfig, textConfig]

  IO.println "Starting Homebase App..."
  IO.println s!"Database: Persistent (journal at {journalPath})"
  IO.println s!"Logging: {jsonLogPath} (JSON), {textLogPath} (text)"

  let app := buildApp logger
  app.run "0.0.0.0" 3000

end HomebaseApp

/-- Top-level main entry point for executable -/
def main : IO Unit := HomebaseApp.runApp
