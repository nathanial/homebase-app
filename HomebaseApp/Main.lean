/-
  HomebaseApp.Main - Application setup and entry point
-/
import Loom
import Loom.Stencil
import Ledger
import Chronicle
import HomebaseApp.Models
import HomebaseApp.Pages
import HomebaseApp.TemplateValidation

-- Validate all templates at compile time
-- This will fail the build if any template has a parse error
#validate_stencil_templates

namespace HomebaseApp

open Loom
open Ledger
open HomebaseApp.Models
open HomebaseApp.Pages

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

/-- Build the application with all routes using persistent database -/
def buildApp (logger : Chronicle.MultiLogger) : App :=
  Loom.app config
    |>.withLogger logger
    |>.use Middleware.methodOverride
    |>.use (Loom.Chronicle.fileLoggingMulti logger)
    |>.use Middleware.securityHeaders
    |>.sseEndpoint "/events/kanban" "kanban"
    |>.sseEndpoint "/events/chat" "chat"
    |>.sseEndpoint "/events/time" "time"
    |>.sseEndpoint "/events/gallery" "gallery"
    |>.sseEndpoint "/events/notebook" "notebook"
    |>.sseEndpoint "/events/health" "health"
    |>.sseEndpoint "/events/recipes" "recipes"
    |>.sseEndpoint "/events/news" "news"
    |>.sseEndpoint "/events/novels" "novels"
    |>.sseEndpoint "/events/hot-reload" "hot-reload"
    |> registerPages
    |>.withPersistentDatabase journalPath
    |>.withStencil { templateDir := "templates", extension := ".html.hbs", hotReload := true }

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
