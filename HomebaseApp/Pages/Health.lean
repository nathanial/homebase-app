/-
  HomebaseApp.Pages.Health - Health tracking (weight, exercise, medication, notes)
-/
import Scribe
import Loom
import Loom.SSE
import Ledger
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Helpers
import HomebaseApp.Middleware

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

/-! ## Helpers -/

/-- Get current time in milliseconds -/
def healthGetNowMs : IO Nat := do
  let output ← IO.Process.output { cmd := "date", args := #["+%s"] }
  let seconds := output.stdout.trim.toNat?.getD 0
  return seconds * 1000

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

/-- Get current user's EntityId -/
def healthGetCurrentUserEid (ctx : Context) : Option EntityId :=
  match currentUserId ctx with
  | some idStr => idStr.toNat?.map fun n => ⟨n⟩
  | none => none

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

/-- Get CSS class for entry type -/
def healthEntryTypeClass (entryType : String) : String :=
  s!"health-entry-{entryType}"

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

/-! ## View Helpers -/

/-- Attribute to clear modal after form submission -/
def healthModalClearAttr : Attr :=
  ⟨"hx-on::after-request", "document.getElementById('modal-container').innerHTML = ''"⟩

/-- Get active class for filter tab -/
def healthFilterClass (currentFilter target : String) : String :=
  if currentFilter == target then "health-filter-tab active" else "health-filter-tab"

/-- Render entry type filter tabs -/
def healthRenderFilterTabs (currentFilter : String) : HtmlM Unit := do
  div [class_ "health-filters"] do
    a [href_ "/health", class_ (healthFilterClass currentFilter "all")] (text "All")
    a [href_ "/health?type=weight", class_ (healthFilterClass currentFilter "weight")] do
      span [] (text "⚖️")
      text " Weight"
    a [href_ "/health?type=exercise", class_ (healthFilterClass currentFilter "exercise")] do
      span [] (text "🏃")
      text " Exercise"
    a [href_ "/health?type=medication", class_ (healthFilterClass currentFilter "medication")] do
      span [] (text "💊")
      text " Medication"
    a [href_ "/health?type=note", class_ (healthFilterClass currentFilter "note")] do
      span [] (text "📝")
      text " Notes"

/-- Render stats cards -/
def healthRenderStats (entries : List HealthEntryView) (latestWeight : Option HealthEntryView) : HtmlM Unit := do
  div [class_ "health-stats"] do
    -- Latest weight card
    div [class_ "health-stat-card"] do
      div [class_ "health-stat-icon"] (text "⚖️")
      div [class_ "health-stat-content"] do
        match latestWeight with
        | some w =>
          div [class_ "health-stat-value"] (text s!"{w.value} {w.unit}")
          div [class_ "health-stat-label"] (text "Current Weight")
        | none =>
          div [class_ "health-stat-value"] (text "—")
          div [class_ "health-stat-label"] (text "No weight logged")
    -- Total entries card
    div [class_ "health-stat-card"] do
      div [class_ "health-stat-icon"] (text "📊")
      div [class_ "health-stat-content"] do
        div [class_ "health-stat-value"] (text (toString entries.length))
        div [class_ "health-stat-label"] (text "Total Entries")
    -- Exercise entries this week (simplified - just count)
    let exerciseCount := (entries.filter (·.entryType == "exercise")).length
    div [class_ "health-stat-card"] do
      div [class_ "health-stat-icon"] (text "🏃")
      div [class_ "health-stat-content"] do
        div [class_ "health-stat-value"] (text (toString exerciseCount))
        div [class_ "health-stat-label"] (text "Exercise Logs")

/-- Render a single health entry row -/
def healthRenderEntryRow (entry : HealthEntryView) (now : Nat) : HtmlM Unit := do
  div [id_ s!"entry-{entry.id}", class_ s!"health-entry-row {healthEntryTypeClass entry.entryType}"] do
    div [class_ "health-entry-icon"] (text (healthEntryTypeIcon entry.entryType))
    div [class_ "health-entry-main"] do
      div [class_ "health-entry-header"] do
        span [class_ "health-entry-type"] (text (healthEntryTypeLabel entry.entryType))
        span [class_ "health-entry-time"] (text (healthFormatRelativeTime entry.recordedAt now))
      div [class_ "health-entry-value"] do
        if entry.value.isEmpty then
          text "—"
        else
          text s!"{entry.value}"
          if !entry.unit.isEmpty then
            span [class_ "health-entry-unit"] (text s!" {entry.unit}")
      if !entry.notes.isEmpty then
        p [class_ "health-entry-notes"] (text entry.notes)
    div [class_ "health-entry-actions"] do
      button [hx_get s!"/health/entry/{entry.id}/edit", hx_target "#modal-container",
              hx_swap "innerHTML", class_ "btn-icon", title_ "Edit"] (text "e")
      button [hx_delete s!"/health/entry/{entry.id}", hx_swap "none",
              hx_confirm "Delete this entry?",
              class_ "btn-icon btn-icon-danger", title_ "Delete"] (text "x")

/-- Render entries list -/
def healthRenderEntriesList (entries : List HealthEntryView) (now : Nat) : HtmlM Unit := do
  if entries.isEmpty then
    div [class_ "health-empty"] do
      div [class_ "health-empty-icon"] (text "🏥")
      p [] (text "No health entries yet")
      p [class_ "text-muted"] (text "Start tracking your health!")
  else
    div [class_ "health-entries-list"] do
      for entry in entries do healthRenderEntryRow entry now

/-- Main health page content -/
def healthPageContent (ctx : Context) (entries : List HealthEntryView) (filter : String)
    (latestWeight : Option HealthEntryView) (now : Nat) : HtmlM Unit := do
  div [class_ "health-container"] do
    -- Header
    div [class_ "health-header"] do
      h1 [] (text "Health")
      button [hx_get "/health/log/new", hx_target "#modal-container",
              hx_swap "innerHTML", class_ "btn btn-primary"] (text "+ Log Entry")
    -- Stats
    healthRenderStats entries latestWeight
    -- Filters
    healthRenderFilterTabs filter
    -- Entries
    div [id_ "health-entries"] do
      healthRenderEntriesList entries now
    -- Modal container
    div [id_ "modal-container"] (pure ())
    -- SSE script
    script [src_ "/js/health.js"]

/-! ## Pages -/

-- Main health page
view healthPage "/health" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let filter := ctx.paramD "type" "all"
  let now ← healthGetNowMs
  let entries := if filter == "all" then getHealthEntries ctx else getHealthEntriesByType ctx filter
  let latestWeight := getLatestWeight ctx
  html (Shared.render ctx "Health - Homebase" "/health"
    (healthPageContent ctx entries filter latestWeight now))

-- New entry form (modal)
view healthNewEntryForm "/health/log/new" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  html (HtmlM.render do
    div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
      div [class_ "modal-container modal-md"] do
        h3 [class_ "modal-title"] (text "Log Health Entry")
        form [hx_post "/health/log", hx_swap "none", healthModalClearAttr] do
          csrfField ctx.csrfToken
          div [class_ "form-stack"] do
            div [class_ "form-group"] do
              label [for_ "entryType", class_ "form-label"] (text "Type")
              select [name_ "entryType", id_ "entryType", class_ "form-select",
                      attr_ "onchange" "document.getElementById('unit-field').value = this.options[this.selectedIndex].dataset.unit || ''"] do
                for (t, label, unit) in healthEntryTypes do
                  option [value_ t, data_ "unit" unit] label
            div [class_ "form-group"] do
              label [for_ "value", class_ "form-label"] (text "Value")
              input [type_ "text", name_ "value", id_ "value",
                     class_ "form-input", placeholder_ "e.g., 70 or 30"]
            div [class_ "form-group"] do
              label [for_ "unit", class_ "form-label"] (text "Unit")
              input [type_ "text", name_ "unit", id_ "unit-field",
                     value_ "kg", class_ "form-input", placeholder_ "e.g., kg, minutes"]
            div [class_ "form-group"] do
              label [for_ "notes", class_ "form-label"] (text "Notes (optional)")
              textarea [name_ "notes", id_ "notes", class_ "form-textarea", rows_ 3,
                        placeholder_ "Any additional notes..."] ""
            div [class_ "form-actions"] do
              button [type_ "button", class_ "btn btn-secondary",
                      attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
              button [type_ "submit", class_ "btn btn-primary"] (text "Log Entry"))

-- Edit entry form (modal)
view healthEditEntryForm "/health/entry/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getHealthEntry ctx id with
  | none => notFound "Entry not found"
  | some entry =>
    html (HtmlM.render do
      div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
        div [class_ "modal-container modal-md"] do
          h3 [class_ "modal-title"] (text "Edit Health Entry")
          form [hx_put s!"/health/entry/{id}", hx_swap "none", healthModalClearAttr] do
            csrfField ctx.csrfToken
            div [class_ "form-stack"] do
              div [class_ "form-group"] do
                label [for_ "entryType", class_ "form-label"] (text "Type")
                select [name_ "entryType", id_ "entryType", class_ "form-select"] do
                  for (t, label, _) in healthEntryTypes do
                    if t == entry.entryType then
                      option [value_ t, selected_] label
                    else
                      option [value_ t] label
              div [class_ "form-group"] do
                label [for_ "value", class_ "form-label"] (text "Value")
                input [type_ "text", name_ "value", id_ "value",
                       value_ entry.value, class_ "form-input"]
              div [class_ "form-group"] do
                label [for_ "unit", class_ "form-label"] (text "Unit")
                input [type_ "text", name_ "unit", id_ "unit",
                       value_ entry.unit, class_ "form-input"]
              div [class_ "form-group"] do
                label [for_ "notes", class_ "form-label"] (text "Notes")
                textarea [name_ "notes", id_ "notes", class_ "form-textarea", rows_ 3] entry.notes
              div [class_ "form-actions"] do
                button [type_ "button", class_ "btn btn-secondary",
                        attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
                button [type_ "submit", class_ "btn btn-primary"] (text "Save Changes"))

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
