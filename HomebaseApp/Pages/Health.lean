/-
  HomebaseApp.Pages.Health - Health tracking (weight, exercise, medication, notes)
-/
import Scribe
import Loom
import Loom.SSE
import Loom.Stencil
import Stencil
import Ledger
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Helpers
import HomebaseApp.Middleware
import HomebaseApp.StencilHelpers

namespace HomebaseApp.Pages

open Scribe
open Loom hiding Action
open Loom.Page
open Loom.ActionM
open Loom.AuditTxM (audit)
open Loom.Json
open Ledger
open HomebaseApp.Shared hiding isLoggedIn isAdmin
open HomebaseApp.Models
open HomebaseApp.Entities
open HomebaseApp.Helpers
open HomebaseApp.StencilHelpers

/-! ## Constants -/

/-- Entry type options -/
def healthEntryTypes : List (String × String × String) :=
  [("weight", "Weight", "kg"),
   ("exercise", "Exercise", "minutes"),
   ("medication", "Medication", "dose"),
   ("note", "Note", "")]

/-! ## View Models -/

/-- View model for a health entry -/
structure HealthEntryView where
  id : Nat
  entryType : String
  value : String
  unit : String
  notes : String
  recordedAt : Nat
  createdAt : Nat
  deriving Inhabited

/-! ## Stencil Value Helpers -/

/-- Format relative time -/
def healthFormatRelativeTime (timestamp now : Nat) : String :=
  let diffMs := now - timestamp
  let diffSecs := diffMs / 1000
  let diffMins := diffSecs / 60
  let diffHours := diffMins / 60
  let diffDays := diffHours / 24
  if diffDays > 0 then s!"{diffDays}d ago"
  else if diffHours > 0 then s!"{diffHours}h ago"
  else if diffMins > 0 then s!"{diffMins}m ago"
  else "just now"

/-- Get entry type label -/
def healthEntryTypeLabel (entryType : String) : String :=
  match healthEntryTypes.find? (fun (t, _, _) => t == entryType) with
  | some (_, label, _) => label
  | none => entryType

/-- Get entry type icon -/
def healthEntryTypeIcon (entryType : String) : String :=
  match entryType with
  | "weight" => "⚖️"
  | "exercise" => "🏃"
  | "medication" => "💊"
  | "note" => "📝"
  | _ => "📋"

/-- Convert a HealthEntryView to Stencil.Value -/
def healthEntryToValue (entry : HealthEntryView) (now : Nat) : Stencil.Value :=
  .object #[
    ("id", .int (Int.ofNat entry.id)),
    ("entryType", .string entry.entryType),
    ("value", .string entry.value),
    ("unit", .string entry.unit),
    ("notes", .string entry.notes),
    ("hasValue", .bool (!entry.value.isEmpty)),
    ("hasUnit", .bool (!entry.unit.isEmpty)),
    ("hasNotes", .bool (!entry.notes.isEmpty)),
    ("icon", .string (healthEntryTypeIcon entry.entryType)),
    ("typeLabel", .string (healthEntryTypeLabel entry.entryType)),
    ("relativeTime", .string (healthFormatRelativeTime entry.recordedAt now)),
    ("isWeight", .bool (entry.entryType == "weight")),
    ("isExercise", .bool (entry.entryType == "exercise")),
    ("isMedication", .bool (entry.entryType == "medication")),
    ("isNote", .bool (entry.entryType == "note"))
  ]

/-- Convert a list of health entries to Stencil.Value -/
def healthEntriesToValue (entries : List HealthEntryView) (now : Nat) : Stencil.Value :=
  .array (entries.map (healthEntryToValue · now)).toArray

/-! ## Helpers -/

/-- Get current time in milliseconds -/
def healthGetNowMs : IO Nat := do
  let output ← IO.Process.output { cmd := "date", args := #["+%s"] }
  let seconds := output.stdout.trim.toNat?.getD 0
  return seconds * 1000

/-- Get current user's EntityId -/
def healthGetCurrentUserEid (ctx : Context) : Option EntityId :=
  match currentUserId ctx with
  | some idStr => idStr.toNat?.map fun n => ⟨n⟩
  | none => none

/-! ## Database Helpers -/

/-- Get all health entries for current user -/
def getHealthEntries (ctx : Context) : List HealthEntryView :=
  match ctx.database, healthGetCurrentUserEid ctx with
  | some db, some userEid =>
    let entryIds := db.findByAttrValue DbHealthEntry.attr_user (.ref userEid)
    let entries := entryIds.filterMap fun entryId =>
      match DbHealthEntry.pull db entryId with
      | some e =>
        some { id := e.id, entryType := e.entryType, value := e.value,
               unit := e.unit, notes := e.notes, recordedAt := e.recordedAt,
               createdAt := e.createdAt }
      | none => none
    entries.toArray.qsort (fun a b => a.recordedAt > b.recordedAt) |>.toList  -- newest first
  | _, _ => []

/-- Get health entries filtered by type -/
def getHealthEntriesByType (ctx : Context) (entryType : String) : List HealthEntryView :=
  let entries := getHealthEntries ctx
  entries.filter (·.entryType == entryType)

/-- Get a single health entry by ID -/
def getHealthEntry (ctx : Context) (entryId : Nat) : Option HealthEntryView :=
  match ctx.database with
  | some db =>
    let eid : EntityId := ⟨entryId⟩
    match DbHealthEntry.pull db eid with
    | some e =>
      some { id := e.id, entryType := e.entryType, value := e.value,
             unit := e.unit, notes := e.notes, recordedAt := e.recordedAt,
             createdAt := e.createdAt }
    | none => none
  | none => none

/-- Get the latest weight entry -/
def getLatestWeight (ctx : Context) : Option HealthEntryView :=
  let entries := getHealthEntriesByType ctx "weight"
  entries.head?

/-! ## Pages -/

-- Main health page
view healthPage "/health" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let filter := ctx.paramD "type" "all"
  let now ← healthGetNowMs
  let entries := if filter == "all" then getHealthEntries ctx else getHealthEntriesByType ctx filter
  let latestWeight := getLatestWeight ctx
  let exerciseCount := (entries.filter (·.entryType == "exercise")).length
  let data := pageContext ctx "Health" PageId.health
    (.object #[
      ("entries", healthEntriesToValue entries now),
      ("hasEntries", .bool (!entries.isEmpty)),
      ("totalEntries", .int (Int.ofNat entries.length)),
      ("exerciseCount", .int (Int.ofNat exerciseCount)),
      ("hasLatestWeight", .bool latestWeight.isSome),
      ("latestWeight", match latestWeight with
        | some w => .object #[("value", .string w.value), ("unit", .string w.unit)]
        | none => .null),
      ("filterAll", .bool (filter == "all")),
      ("filterWeight", .bool (filter == "weight")),
      ("filterExercise", .bool (filter == "exercise")),
      ("filterMedication", .bool (filter == "medication")),
      ("filterNote", .bool (filter == "note"))
    ])
  Loom.Stencil.ActionM.renderWithLayout "app" "health/index" data

-- New entry form (modal)
view healthNewEntryForm "/health/log/new" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let data : Stencil.Value := .object #[("csrfToken", .string ctx.csrfToken)]
  Loom.Stencil.ActionM.render "health/new" data

-- Edit entry form (modal)
view healthEditEntryForm "/health/entry/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getHealthEntry ctx id with
  | none => notFound "Entry not found"
  | some entry =>
    let now ← healthGetNowMs
    let data := mergeContext (healthEntryToValue entry now)
      (.object #[("csrfToken", .string ctx.csrfToken)])
    Loom.Stencil.ActionM.render "health/edit" data

/-! ## Actions -/

-- Create health entry
action healthLogEntry "/health/log" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let entryType := ctx.paramD "entryType" "note"
  let value := ctx.paramD "value" ""
  let unit := ctx.paramD "unit" ""
  let notes := ctx.paramD "notes" ""
  match healthGetCurrentUserEid ctx with
  | none => redirect "/login"
  | some userEid =>
    let now ← healthGetNowMs
    let (_, _) ← withNewEntityAudit! fun eid => do
      let entry : DbHealthEntry := {
        id := eid.id.toNat, entryType := entryType, value := value,
        unit := unit, notes := notes, recordedAt := now, createdAt := now, user := userEid
      }
      DbHealthEntry.TxM.create eid entry
      audit "CREATE" "health-entry" eid.id.toNat [("type", entryType), ("value", value)]
    let _ ← SSE.publishEvent "health" "entry-created" (jsonStr! { entryType, value })
    redirect "/health"

-- Update health entry
action healthUpdateEntry "/health/entry/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let entryType := ctx.paramD "entryType" "note"
  let value := ctx.paramD "value" ""
  let unit := ctx.paramD "unit" ""
  let notes := ctx.paramD "notes" ""
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbHealthEntry.TxM.setEntryType eid entryType
    DbHealthEntry.TxM.setValue eid value
    DbHealthEntry.TxM.setUnit eid unit
    DbHealthEntry.TxM.setNotes eid notes
    audit "UPDATE" "health-entry" id [("type", entryType), ("value", value)]
  let entryId := id
  let _ ← SSE.publishEvent "health" "entry-updated" (jsonStr! { entryId, entryType, value })
  redirect "/health"

-- Delete health entry
action healthDeleteEntry "/health/entry/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbHealthEntry.TxM.delete eid
    audit "DELETE" "health-entry" id []
  let entryId := id
  let _ ← SSE.publishEvent "health" "entry-deleted" (jsonStr! { entryId })
  redirect "/health"

end HomebaseApp.Pages
