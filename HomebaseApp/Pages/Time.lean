/-
  HomebaseApp.Pages.Time - Time tracking pages
-/
import Scribe
import Loom
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

/-- Get current time in milliseconds -/
def timeGetNowMs : IO Nat := IO.monoMsNow

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

/-! ## View Helpers -/

/-- Attribute to clear modal after form submission -/
def timeModalClearAttr : Attr :=
  ⟨"hx-on::after-request", "document.getElementById('modal-container').innerHTML = ''"⟩

/-- Get category badge color class -/
def categoryClass (category : String) : String :=
  match category.toLower with
  | "work" => "category-work"
  | "personal" => "category-personal"
  | "learning" => "category-learning"
  | "health" => "category-health"
  | _ => "category-other"

/-- Render category badge -/
def renderCategory (category : String) : HtmlM Unit := do
  span [class_ s!"time-category {categoryClass category}"] (text category)

/-- Render the active timer section -/
def renderTimer (timer : Option Timer) (nowMs : Nat) : HtmlM Unit := do
  div [class_ "time-timer-section"] do
    match timer with
    | some t =>
      let elapsed := (nowMs - t.startTime) / 1000
      div [class_ "time-timer-active"] do
        div [class_ "time-timer-display running"] do
          span [id_ "timer-value", data_ "start" (toString t.startTime)] (text (formatDuration elapsed))
        div [class_ "time-timer-info"] do
          p [class_ "time-timer-description"] (text t.description)
          renderCategory t.category
        form [hx_post "/time/stop", hx_swap "none", class_ "time-timer-form"] do
          button [type_ "submit", class_ "btn btn-danger"] (text "Stop Timer")
    | none =>
      div [class_ "time-timer-inactive"] do
        div [class_ "time-timer-display"] do
          span [id_ "timer-value"] (text "00:00:00")
        form [hx_post "/time/start", hx_swap "none", class_ "time-timer-form"] do
          div [class_ "form-row"] do
            input [type_ "text", name_ "description", placeholder_ "What are you working on?",
                   class_ "form-input", required_]
            select [name_ "category", class_ "form-select"] do
              for categ in defaultCategories do
                option [value_ categ] categ
            button [type_ "submit", class_ "btn btn-primary"] (text "Start")

/-- Render a time entry row -/
def renderEntryRow (entry : TimeEntry) : HtmlM Unit := do
  tr [id_ s!"entry-{entry.id}", class_ "time-entry-row"] do
    td [class_ "time-entry-time"] do
      text s!"{formatTimeOfDay entry.startTime} - {formatTimeOfDay entry.endTime}"
    td [class_ "time-entry-description"] (text entry.description)
    td [class_ "time-entry-category"] (renderCategory entry.category)
    td [class_ "time-entry-duration"] (text (formatDurationShort entry.duration))
    td [class_ "time-entry-actions"] do
      button [hx_get s!"/time/entry/{entry.id}/edit", hx_target "#modal-container",
              hx_swap "innerHTML", class_ "btn-icon", title_ "Edit"] (text "e")
      button [hx_delete s!"/time/entry/{entry.id}", hx_swap "none",
              hx_confirm "Delete this time entry?",
              class_ "btn-icon btn-icon-danger", title_ "Delete"] (text "x")

/-- Render time entries table -/
def renderEntriesTable (entries : List TimeEntry) : HtmlM Unit := do
  if entries.isEmpty then
    div [class_ "time-empty"] do
      p [] (text "No time entries for today. Start tracking!")
  else
    table [class_ "time-entries-table"] do
      thead [] do
        tr [] do
          th [] (text "Time")
          th [] (text "Description")
          th [] (text "Category")
          th [] (text "Duration")
          th [] (text "Actions")
      tbody [] do
        for entry in entries do renderEntryRow entry

/-- Render category summary bar -/
def renderCategorySummary (categories : List (String × Nat)) (total : Nat) : HtmlM Unit := do
  if categories.isEmpty then pure ()
  else
    div [class_ "time-summary-bar"] do
      for (cat, dur) in categories do
        let pct := if total > 0 then (dur * 100) / total else 0
        div [class_ s!"time-summary-segment {categoryClass cat}",
             style_ s!"flex-basis: {pct}%", title_ s!"{cat}: {formatDurationShort dur}"] (pure ())

/-- Render today's summary -/
def renderTodaySummary (entries : List TimeEntry) : HtmlM Unit := do
  let total := totalDuration entries
  let categories := groupByCategory entries
  div [class_ "time-today-summary"] do
    div [class_ "time-summary-header"] do
      h2 [] (text "Today")
      span [class_ "time-summary-total"] (text (formatDurationShort total))
    renderCategorySummary categories total

/-- Main time page content -/
def timePageContent (ctx : Context) (timer : Option Timer) (todayEntries : List TimeEntry) (nowMs : Nat) : HtmlM Unit := do
  div [class_ "time-container"] do
    -- Timer section
    renderTimer timer nowMs
    -- Today's summary
    renderTodaySummary todayEntries
    -- Today's entries
    div [class_ "time-entries-section"] do
      div [class_ "time-entries-header"] do
        h3 [] (text "Time Entries")
        div [class_ "time-entries-actions"] do
          button [hx_get "/time/entry/add", hx_target "#modal-container",
                  hx_swap "innerHTML", class_ "btn btn-secondary btn-sm"] (text "+ Manual Entry")
          a [href_ "/time/week", class_ "btn btn-secondary btn-sm"] (text "Weekly Report")
      div [id_ "entries-container"] do
        renderEntriesTable todayEntries
    -- Modal container
    div [id_ "modal-container"] (pure ())
    -- Timer update script
    script [type_ "text/javascript"] "(function() { const timerEl = document.getElementById('timer-value'); if (!timerEl || !timerEl.dataset.start) return; const startTime = parseInt(timerEl.dataset.start); function update() { const elapsed = Math.floor((Date.now() - startTime) / 1000); const h = Math.floor(elapsed / 3600); const m = Math.floor((elapsed % 3600) / 60); const s = elapsed % 60; const pad = n => n.toString().padStart(2, '0'); timerEl.textContent = pad(h) + ':' + pad(m) + ':' + pad(s); } update(); setInterval(update, 1000); })();"

/-- Weekly summary content -/
def weekSummaryContent (_ctx : Context) (entries : List TimeEntry) (weekStartMs : Nat) : HtmlM Unit := do
  let total := totalDuration entries
  let categories := groupByCategory entries
  let msPerDay := 24 * 60 * 60 * 1000
  div [class_ "time-container"] do
    div [class_ "time-week-header"] do
      h1 [] (text "Weekly Summary")
      a [href_ "/time", class_ "btn btn-secondary"] (text "Back to Today")
    -- Total time card
    div [class_ "time-week-total"] do
      h2 [] (text "Total Time")
      span [class_ "time-week-total-value"] (text (formatDurationShort total))
    -- Category breakdown
    div [class_ "time-week-categories"] do
      h3 [] (text "By Category")
      renderCategorySummary categories total
      div [class_ "time-category-list"] do
        for (cat, dur) in categories do
          div [class_ "time-category-item"] do
            renderCategory cat
            span [class_ "time-category-duration"] (text (formatDurationShort dur))
    -- Day-by-day breakdown
    div [class_ "time-week-days"] do
      h3 [] (text "By Day")
      for i in [0:7] do
        let dayStart := weekStartMs + i * msPerDay
        let dayEntries := entries.filter fun e => e.startTime >= dayStart && e.startTime < dayStart + msPerDay
        let dayTotal := totalDuration dayEntries
        if dayTotal > 0 then
          div [class_ "time-day-row"] do
            span [class_ "time-day-label"] (text s!"Day {i + 1}")
            span [class_ "time-day-duration"] (text (formatDurationShort dayTotal))

/-! ## Pages -/

-- Main time tracking page
view timePage "/time" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let nowMs ← timeGetNowMs
  let todayStart := getStartOfToday nowMs
  let timer := getActiveTimer ctx
  let todayEntries := getTimeEntriesForDay ctx todayStart
  html (Shared.render ctx "Time - Homebase" "/time" (timePageContent ctx timer todayEntries nowMs))

-- Weekly summary page
view timeWeek "/time/week" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let nowMs ← timeGetNowMs
  let weekStart := getStartOfWeek nowMs
  let entries := getTimeEntriesInRange ctx weekStart (weekStart + 7 * 24 * 60 * 60 * 1000)
  html (Shared.render ctx "Weekly Summary - Homebase" "/time" (weekSummaryContent ctx entries weekStart))

-- Entries table refresh (for HTMX)
view timeEntries "/time/entries" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let nowMs ← timeGetNowMs
  let todayStart := getStartOfToday nowMs
  let todayEntries := getTimeEntriesForDay ctx todayStart
  html (HtmlM.render (renderEntriesTable todayEntries))

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
    redirect "/time"
  | _, _ => redirect "/time"

-- Add manual entry form
view timeAddEntryForm "/time/entry/add" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  html (HtmlM.render do
    div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
      div [class_ "modal-container modal-md"] do
        h3 [class_ "modal-title"] (text "Add Time Entry")
        form [hx_post "/time/entry", hx_swap "none", timeModalClearAttr] do
          csrfField ctx.csrfToken
          div [class_ "form-stack"] do
            div [class_ "form-group"] do
              label [for_ "description", class_ "form-label"] (text "Description")
              input [type_ "text", name_ "description", id_ "description",
                     class_ "form-input", required_, autofocus_]
            div [class_ "form-group"] do
              label [for_ "startTime", class_ "form-label"] (text "Start Time")
              input [type_ "time", name_ "startTime", id_ "startTime", class_ "form-input", required_]
            div [class_ "form-group"] do
              label [for_ "endTime", class_ "form-label"] (text "End Time")
              input [type_ "time", name_ "endTime", id_ "endTime", class_ "form-input", required_]
            div [class_ "form-group"] do
              label [for_ "category", class_ "form-label"] (text "Category")
              select [name_ "category", id_ "category", class_ "form-select"] do
                for categ in defaultCategories do
                  option [value_ categ] categ
            div [class_ "form-actions"] do
              button [type_ "button", class_ "btn btn-secondary",
                      attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
              button [type_ "submit", class_ "btn btn-primary"] (text "Add Entry"))

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
    redirect "/time"
  | _, _, _ => badRequest "Invalid time format or not logged in"

-- Edit entry form
view timeEditEntryForm "/time/entry/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getTimeEntry ctx id with
  | none => notFound "Entry not found"
  | some entry =>
    html (HtmlM.render do
      div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
        div [class_ "modal-container modal-md"] do
          h3 [class_ "modal-title"] (text "Edit Time Entry")
          form [hx_put s!"/time/entry/{id}", hx_swap "none", timeModalClearAttr] do
            csrfField ctx.csrfToken
            div [class_ "form-stack"] do
              div [class_ "form-group"] do
                label [for_ "description", class_ "form-label"] (text "Description")
                input [type_ "text", name_ "description", id_ "description",
                       value_ entry.description, class_ "form-input", required_]
              div [class_ "form-group"] do
                label [for_ "category", class_ "form-label"] (text "Category")
                select [name_ "category", id_ "category", class_ "form-select"] do
                  for categ in defaultCategories do
                    if categ == entry.category then
                      option [value_ categ, selected_] categ
                    else
                      option [value_ categ] categ
              div [class_ "form-actions"] do
                button [type_ "button", class_ "btn btn-secondary",
                        attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
                button [type_ "submit", class_ "btn btn-primary"] (text "Save Changes"))

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
  redirect "/time"

-- Delete entry
action timeDeleteEntry "/time/entry/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbTimeEntry.TxM.delete eid
    audit "DELETE" "time-entry" id []
  redirect "/time"

end HomebaseApp.Pages
