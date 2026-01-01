/-
  HomebaseApp.Pages.Time - Time tracking pages
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

/-! ## Data Structures -/

/-- Default time categories -/
def defaultCategories : List String := ["Work", "Personal", "Learning", "Health", "Other"]

/-- View model for a time entry -/
structure TimeEntry where
  id : Nat
  description : String
  startTime : Nat
  endTime : Nat
  duration : Nat       -- in seconds
  category : String
  deriving Inhabited

/-- View model for an active timer -/
structure Timer where
  id : Nat
  description : String
  startTime : Nat
  category : String
  deriving Inhabited

/-! ## Time Formatting Helpers -/

/-- Format duration in seconds to HH:MM:SS -/
def formatDuration (seconds : Nat) : String :=
  let hours := seconds / 3600
  let minutes := (seconds % 3600) / 60
  let secs := seconds % 60
  let pad (n : Nat) : String := if n < 10 then s!"0{n}" else toString n
  s!"{pad hours}:{pad minutes}:{pad secs}"

/-- Format duration in a human-readable way (e.g., "2h 30m") -/
def formatDurationShort (seconds : Nat) : String :=
  let hours := seconds / 3600
  let minutes := (seconds % 3600) / 60
  if hours > 0 then
    if minutes > 0 then s!"{hours}h {minutes}m" else s!"{hours}h"
  else if minutes > 0 then s!"{minutes}m"
  else s!"{seconds}s"

/-- Get current wall clock time in milliseconds since Unix epoch.
    Uses shell command since Lean 4 doesn't have built-in wall clock time. -/
def timeGetNowMs : IO Nat := do
  -- Use 'date' command to get Unix timestamp in milliseconds
  -- macOS: date +%s000 (seconds with 000 appended for ms precision)
  -- For actual milliseconds on macOS, we'd need gdate or use seconds * 1000
  let output ← IO.Process.output { cmd := "date", args := #["+%s"] }
  let seconds := output.stdout.trim.toNat?.getD 0
  return seconds * 1000

/-- Get start of today (midnight) in milliseconds - approximation -/
def getStartOfToday (nowMs : Nat) : Nat :=
  -- Approximate: assume day boundary is at midnight UTC
  let msPerDay := 24 * 60 * 60 * 1000
  (nowMs / msPerDay) * msPerDay

/-- Get start of this week (Monday) in milliseconds -/
def getStartOfWeek (nowMs : Nat) : Nat :=
  let msPerDay := 24 * 60 * 60 * 1000
  let msPerWeek := 7 * msPerDay
  -- Approximate week start
  (nowMs / msPerWeek) * msPerWeek

/-- Format timestamp to time of day (HH:MM) -/
def formatTimeOfDay (ms : Nat) : String :=
  let totalSeconds := ms / 1000
  let hours := (totalSeconds / 3600) % 24
  let minutes := (totalSeconds % 3600) / 60
  let pad (n : Nat) : String := if n < 10 then s!"0{n}" else toString n
  s!"{pad hours}:{pad minutes}"

/-! ## Database Helpers -/

/-- Get current user's EntityId -/
def getCurrentUserEid (ctx : Context) : Option EntityId :=
  match currentUserId ctx with
  | some idStr => idStr.toNat?.map fun n => ⟨n⟩
  | none => none

/-- Get active timer for current user -/
def getActiveTimer (ctx : Context) : Option Timer :=
  match ctx.database, getCurrentUserEid ctx with
  | some db, some userEid =>
    let timerIds := db.findByAttrValue DbTimer.attr_user (.ref userEid)
    -- Return the first timer (should only be one per user)
    timerIds.head?.bind fun timerId =>
      match DbTimer.pull db timerId with
      | some t => some { id := t.id, description := t.description, startTime := t.startTime, category := t.category }
      | none => none
  | _, _ => none

/-- Get time entries for current user on a given day -/
def getTimeEntriesForDay (ctx : Context) (dayStartMs : Nat) : List TimeEntry :=
  match ctx.database, getCurrentUserEid ctx with
  | some db, some userEid =>
    let entryIds := db.findByAttrValue DbTimeEntry.attr_user (.ref userEid)
    let dayEndMs := dayStartMs + 24 * 60 * 60 * 1000
    let entries := entryIds.filterMap fun entryId =>
      match DbTimeEntry.pull db entryId with
      | some e =>
        -- Filter to entries that started on this day
        if e.startTime >= dayStartMs && e.startTime < dayEndMs then
          some { id := e.id, description := e.description, startTime := e.startTime,
                 endTime := e.endTime, duration := e.duration, category := e.category }
        else none
      | none => none
    entries.toArray.qsort (fun a b => a.startTime > b.startTime) |>.toList  -- newest first
  | _, _ => []

/-- Get time entries for current user within a time range -/
def getTimeEntriesInRange (ctx : Context) (startMs endMs : Nat) : List TimeEntry :=
  match ctx.database, getCurrentUserEid ctx with
  | some db, some userEid =>
    let entryIds := db.findByAttrValue DbTimeEntry.attr_user (.ref userEid)
    let entries := entryIds.filterMap fun entryId =>
      match DbTimeEntry.pull db entryId with
      | some e =>
        if e.startTime >= startMs && e.startTime < endMs then
          some { id := e.id, description := e.description, startTime := e.startTime,
                 endTime := e.endTime, duration := e.duration, category := e.category }
        else none
      | none => none
    entries.toArray.qsort (fun a b => a.startTime > b.startTime) |>.toList
  | _, _ => []

/-- Get a single time entry by ID -/
def getTimeEntry (ctx : Context) (entryId : Nat) : Option TimeEntry :=
  match ctx.database with
  | some db =>
    let eid : EntityId := ⟨entryId⟩
    match DbTimeEntry.pull db eid with
    | some e => some { id := e.id, description := e.description, startTime := e.startTime,
                       endTime := e.endTime, duration := e.duration, category := e.category }
    | none => none
  | none => none

/-- Calculate total duration for a list of entries -/
def totalDuration (entries : List TimeEntry) : Nat :=
  entries.foldl (fun acc e => acc + e.duration) 0

/-- Group entries by category and sum durations -/
def groupByCategory (entries : List TimeEntry) : List (String × Nat) :=
  let grouped := entries.foldl (fun acc e =>
    match acc.find? (fun (cat, _) => cat == e.category) with
    | some _ => acc.map fun (cat, dur) => if cat == e.category then (cat, dur + e.duration) else (cat, dur)
    | none => acc ++ [(e.category, e.duration)]
  ) []
  grouped.toArray.qsort (fun a b => a.2 > b.2) |>.toList  -- sort by duration descending

/-! ## Stencil Value Helpers -/

/-- Get category class for styling -/
def timeCategoryClass (category : String) : String :=
  match category.toLower with
  | "work" => "category-work"
  | "personal" => "category-personal"
  | "learning" => "category-learning"
  | "health" => "category-health"
  | _ => "category-other"

/-- Convert a time entry to Stencil.Value -/
def timeEntryToValue (entry : TimeEntry) : Stencil.Value :=
  .object #[
    ("id", .int (Int.ofNat entry.id)),
    ("description", .string entry.description),
    ("category", .string entry.category),
    ("categoryClass", .string (timeCategoryClass entry.category)),
    ("timeRange", .string s!"{formatTimeOfDay entry.startTime} - {formatTimeOfDay entry.endTime}"),
    ("durationFormatted", .string (formatDurationShort entry.duration)),
    ("duration", .int (Int.ofNat entry.duration))
  ]

/-- Convert timer to Stencil.Value -/
def timerToValue (timer : Timer) (nowMs : Nat) : Stencil.Value :=
  let elapsed := (nowMs - timer.startTime) / 1000
  .object #[
    ("id", .int (Int.ofNat timer.id)),
    ("description", .string timer.description),
    ("category", .string timer.category),
    ("categoryClass", .string (timeCategoryClass timer.category)),
    ("startTime", .int (Int.ofNat timer.startTime)),
    ("elapsed", .string (formatDuration elapsed))
  ]

/-- Convert category summary to Stencil.Value -/
def categorySummaryToValue (categories : List (String × Nat)) (total : Nat) : Stencil.Value :=
  .array (categories.map fun (cat, dur) =>
    let pct := if total > 0 then (dur * 100) / total else 0
    .object #[
      ("category", .string cat),
      ("categoryClass", .string (timeCategoryClass cat)),
      ("duration", .string (formatDurationShort dur)),
      ("percentage", .int (Int.ofNat pct))
    ]
  ).toArray

/-- Build time page data for Stencil -/
def timePageData (ctx : Context) (timer : Option Timer) (entries : List TimeEntry) (nowMs : Nat) : Stencil.Value :=
  let total := totalDuration entries
  let categories := groupByCategory entries
  .object #[
    ("hasActiveTimer", .bool timer.isSome),
    ("timer", match timer with | some t => timerToValue t nowMs | none => .null),
    ("timerElapsed", .string (match timer with
      | some t => formatDuration ((nowMs - t.startTime) / 1000)
      | none => "00:00:00")),
    ("categories", .array (defaultCategories.map .string).toArray),
    ("hasEntries", .bool (!entries.isEmpty)),
    ("entries", .array (entries.map timeEntryToValue).toArray),
    ("totalDuration", .string (formatDurationShort total)),
    ("hasCategorySummary", .bool (!categories.isEmpty)),
    ("categorySummary", categorySummaryToValue categories total),
    ("csrfToken", .string ctx.csrfToken)
  ]

/-- Build week page data for Stencil -/
def weekPageData (entries : List TimeEntry) (weekStartMs : Nat) : Stencil.Value :=
  let total := totalDuration entries
  let categories := groupByCategory entries
  let msPerDay := 24 * 60 * 60 * 1000
  let days := (List.range 7).map fun i =>
    let dayStart := weekStartMs + i * msPerDay
    let dayEntries := entries.filter fun e => e.startTime >= dayStart && e.startTime < dayStart + msPerDay
    let dayTotal := totalDuration dayEntries
    .object #[
      ("label", .string s!"Day {i + 1}"),
      ("hasTime", .bool (dayTotal > 0)),
      ("duration", .string (formatDurationShort dayTotal))
    ]
  .object #[
    ("totalDuration", .string (formatDurationShort total)),
    ("hasCategorySummary", .bool (!categories.isEmpty)),
    ("categorySummary", categorySummaryToValue categories total),
    ("days", .array days.toArray)
  ]

/-! ## Pages -/

-- Main time tracking page
view timePage "/time" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let nowMs ← timeGetNowMs
  let todayStart := getStartOfToday nowMs
  let timer := getActiveTimer ctx
  let todayEntries := getTimeEntriesForDay ctx todayStart
  let data := pageContext ctx "Time" PageId.time (timePageData ctx timer todayEntries nowMs)
  Loom.Stencil.ActionM.renderWithLayout "app" "time/index" data

-- Weekly summary page
view timeWeek "/time/week" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let nowMs ← timeGetNowMs
  let weekStart := getStartOfWeek nowMs
  let entries := getTimeEntriesInRange ctx weekStart (weekStart + 7 * 24 * 60 * 60 * 1000)
  let data := pageContext ctx "Weekly Summary" PageId.time (weekPageData entries weekStart)
  Loom.Stencil.ActionM.renderWithLayout "app" "time/week" data

-- Entries table refresh (for HTMX)
view timeEntries "/time/entries" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let nowMs ← timeGetNowMs
  let todayStart := getStartOfToday nowMs
  let todayEntries := getTimeEntriesForDay ctx todayStart
  let data : Stencil.Value := .object #[
    ("hasEntries", .bool (!todayEntries.isEmpty)),
    ("entries", .array (todayEntries.map timeEntryToValue).toArray)
  ]
  Loom.Stencil.ActionM.render "time/entries" data

-- Start timer
action timeStart "/time/start" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let description := ctx.paramD "description" ""
  let category := ctx.paramD "category" "Other"
  if description.isEmpty then return ← badRequest "Description is required"
  -- Check if timer already running
  match getActiveTimer ctx with
  | some _ => redirect "/time"  -- Timer already running
  | none =>
    match getCurrentUserEid ctx with
    | none => redirect "/login"
    | some userEid =>
      let nowMs ← timeGetNowMs
      let (_, _) ← withNewEntityAudit! fun eid => do
        let timer : DbTimer := { id := eid.id.toNat, description := description,
                                 startTime := nowMs, category := category, user := userEid }
        DbTimer.TxM.create eid timer
        audit "CREATE" "timer" eid.id.toNat [("description", description), ("category", category)]
      let _ ← SSE.publishEvent "time" "timer-started" (jsonStr! { description, category })
      redirect "/time"

-- Stop timer
action timeStop "/time/stop" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  match getActiveTimer ctx, getCurrentUserEid ctx with
  | some timer, some userEid =>
    let nowMs ← timeGetNowMs
    let duration := (nowMs - timer.startTime) / 1000  -- seconds
    -- Create time entry
    let (_, _) ← withNewEntityAudit! fun eid => do
      let entry : DbTimeEntry := { id := eid.id.toNat, description := timer.description,
                                   startTime := timer.startTime, endTime := nowMs,
                                   duration := duration, category := timer.category, user := userEid }
      DbTimeEntry.TxM.create eid entry
      audit "CREATE" "time-entry" eid.id.toNat [("description", timer.description),
            ("duration", toString duration), ("category", timer.category)]
    -- Delete timer
    let timerEid : EntityId := ⟨timer.id⟩
    runAuditTx! do
      DbTimer.TxM.delete timerEid
      audit "DELETE" "timer" timer.id []
    let _ ← SSE.publishEvent "time" "timer-stopped" (jsonStr! { "duration" : duration })
    redirect "/time"
  | _, _ => redirect "/time"

-- Add manual entry form
view timeAddEntryForm "/time/entry/add" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let data : Stencil.Value := .object #[
    ("categories", .array (defaultCategories.map .string).toArray),
    ("csrfToken", .string ctx.csrfToken)
  ]
  Loom.Stencil.ActionM.render "time/add" data

-- Create manual entry
action timeCreateEntry "/time/entry" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let description := ctx.paramD "description" ""
  let startTimeStr := ctx.paramD "startTime" ""
  let endTimeStr := ctx.paramD "endTime" ""
  let category := ctx.paramD "category" "Other"
  if description.isEmpty || startTimeStr.isEmpty || endTimeStr.isEmpty then
    return ← badRequest "All fields are required"
  -- Parse time strings (HH:MM format)
  let parseTime (s : String) : Option Nat :=
    match s.splitOn ":" with
    | [hStr, mStr] =>
      match hStr.toNat?, mStr.toNat? with
      | some h, some m => some (h * 3600 + m * 60)
      | _, _ => none
    | _ => none
  match parseTime startTimeStr, parseTime endTimeStr, getCurrentUserEid ctx with
  | some startSecs, some endSecs, some userEid =>
    if endSecs <= startSecs then return ← badRequest "End time must be after start time"
    let nowMs ← timeGetNowMs
    let todayStart := getStartOfToday nowMs
    -- Convert to milliseconds (relative to today)
    let startMs := todayStart + startSecs * 1000
    let endMs := todayStart + endSecs * 1000
    let duration := endSecs - startSecs
    let (_, _) ← withNewEntityAudit! fun eid => do
      let entry : DbTimeEntry := { id := eid.id.toNat, description := description,
                                   startTime := startMs, endTime := endMs,
                                   duration := duration, category := category, user := userEid }
      DbTimeEntry.TxM.create eid entry
      audit "CREATE" "time-entry" eid.id.toNat [("description", description),
            ("duration", toString duration), ("category", category), ("manual", "true")]
    let _ ← SSE.publishEvent "time" "entry-created" (jsonStr! { description, category, "duration" : duration })
    redirect "/time"
  | _, _, _ => badRequest "Invalid time format or not logged in"

-- Edit entry form
view timeEditEntryForm "/time/entry/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getTimeEntry ctx id with
  | none => notFound "Entry not found"
  | some entry =>
    let categories := defaultCategories.map fun cat =>
      .object #[("name", .string cat), ("isSelected", .bool (cat == entry.category))]
    let data : Stencil.Value := .object #[
      ("id", .int (Int.ofNat id)),
      ("description", .string entry.description),
      ("categories", .array categories.toArray),
      ("csrfToken", .string ctx.csrfToken)
    ]
    Loom.Stencil.ActionM.render "time/edit" data

-- Update entry
action timeUpdateEntry "/time/entry/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let description := ctx.paramD "description" ""
  let category := ctx.paramD "category" "Other"
  if description.isEmpty then return ← badRequest "Description is required"
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbTimeEntry.TxM.setDescription eid description
    DbTimeEntry.TxM.setCategory eid category
    audit "UPDATE" "time-entry" id [("description", description), ("category", category)]
  let entryId := id
  let _ ← SSE.publishEvent "time" "entry-updated" (jsonStr! { entryId, description, category })
  redirect "/time"

-- Delete entry
action timeDeleteEntry "/time/entry/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbTimeEntry.TxM.delete eid
    audit "DELETE" "time-entry" id []
  let entryId := id
  let _ ← SSE.publishEvent "time" "entry-deleted" (jsonStr! { entryId })
  redirect "/time"

end HomebaseApp.Pages
