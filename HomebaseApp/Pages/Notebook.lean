/-
  HomebaseApp.Pages.Notebook - Markdown notes with notebook organization
-/
import Scribe
import Loom
import Loom.SSE
import Loom.Htmx
import Loom.Stencil
import Stencil
import Ledger
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Helpers
import HomebaseApp.Middleware
import HomebaseApp.Upload
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

/-! ## View Models -/

/-- View model for a notebook -/
structure NotebookView where
  id : Nat
  title : String
  noteCount : Nat
  createdAt : Nat
  deriving Inhabited

/-- View model for a note -/
structure NoteView where
  id : Nat
  title : String
  content : String
  notebookId : Nat
  createdAt : Nat
  updatedAt : Nat
  version : Nat
  deriving Inhabited

/-! ## Helpers -/

/-- Get current time in milliseconds -/
def notebookGetNowMs : IO Nat := do
  let output ← IO.Process.output { cmd := "date", args := #["+%s"] }
  let seconds := output.stdout.trim.toNat?.getD 0
  return seconds * 1000

/-- Format relative time -/
def notebookFormatRelativeTime (timestamp now : Nat) : String :=
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
def notebookGetCurrentUserEid (ctx : Context) : Option EntityId :=
  match currentUserId ctx with
  | some idStr => idStr.toNat?.map fun n => ⟨n⟩
  | none => none

/-! ## Database Helpers -/

/-- Get all notebooks for current user -/
def getNotebooks (ctx : Context) : List NotebookView :=
  match ctx.database, notebookGetCurrentUserEid ctx with
  | some db, some userEid =>
    let notebookIds := db.findByAttrValue DbNotebook.attr_user (.ref userEid)
    let notebooks := notebookIds.filterMap fun nbId =>
      match DbNotebook.pull db nbId with
      | some nb =>
        -- Count notes in this notebook
        let noteIds := db.findByAttrValue DbNote.attr_notebook (.ref nbId)
        some { id := nb.id, title := nb.title, noteCount := noteIds.length, createdAt := nb.createdAt }
      | none => none
    notebooks.toArray.qsort (fun a b => a.title < b.title) |>.toList  -- alphabetical
  | _, _ => []

/-- Get a single notebook by ID -/
def getNotebook (ctx : Context) (nbId : Nat) : Option NotebookView :=
  match ctx.database with
  | some db =>
    let eid : EntityId := ⟨nbId⟩
    match DbNotebook.pull db eid with
    | some nb =>
      let noteIds := db.findByAttrValue DbNote.attr_notebook (.ref eid)
      some { id := nb.id, title := nb.title, noteCount := noteIds.length, createdAt := nb.createdAt }
    | none => none
  | none => none

/-- Get all notes in a notebook -/
def getNotesInNotebook (ctx : Context) (nbId : Nat) : List NoteView :=
  match ctx.database with
  | some db =>
    let nbEid : EntityId := ⟨nbId⟩
    let noteIds := db.findByAttrValue DbNote.attr_notebook (.ref nbEid)
    let notes := noteIds.filterMap fun noteId =>
      match DbNote.pull db noteId with
      | some note =>
        some { id := note.id, title := note.title, content := note.content,
               notebookId := nbId, createdAt := note.createdAt, updatedAt := note.updatedAt,
               version := note.version }
      | none => none
    notes.toArray.qsort (fun a b => a.updatedAt > b.updatedAt) |>.toList  -- newest first
  | none => []

/-- Get a single note by ID -/
def getNote (ctx : Context) (noteId : Nat) : Option NoteView :=
  match ctx.database with
  | some db =>
    let eid : EntityId := ⟨noteId⟩
    match DbNote.pull db eid with
    | some note =>
      some { id := note.id, title := note.title, content := note.content,
             notebookId := note.notebook.id.toNat, createdAt := note.createdAt,
             updatedAt := note.updatedAt, version := note.version }
    | none => none
  | none => none

/-- Get all notes grouped by notebook ID -/
def getAllNotesGrouped (ctx : Context) (notebooks : List NotebookView) : List (Nat × List NoteView) :=
  notebooks.map fun nb => (nb.id, getNotesInNotebook ctx nb.id)

/-! ## Stencil Value Helpers -/

/-- Convert a note to Stencil.Value -/
def noteToValue (note : NoteView) (selectedNoteId : Option Nat) : Stencil.Value :=
  .object #[
    ("id", .int (Int.ofNat note.id)),
    ("title", .string note.title),
    ("content", .string note.content),
    ("notebookId", .int (Int.ofNat note.notebookId)),
    ("version", .int (Int.ofNat note.version)),
    ("isSelected", .bool (selectedNoteId == some note.id))
  ]

/-- Convert a notebook with its notes to Stencil.Value -/
def notebookWithNotesToValue (nb : NotebookView) (notes : List NoteView)
    (selectedNoteId : Option Nat) : Stencil.Value :=
  let isExpanded := selectedNoteId.any fun selId => notes.any (·.id == selId)
  .object #[
    ("id", .int (Int.ofNat nb.id)),
    ("title", .string nb.title),
    ("noteCount", .int (Int.ofNat nb.noteCount)),
    ("hasNotes", .bool (!notes.isEmpty)),
    ("notes", .array (notes.map (noteToValue · selectedNoteId)).toArray),
    ("expandIcon", .string (if isExpanded then "▼" else "▶")),
    ("notesClass", .string (if isExpanded then "notebook-tree-notes" else "notebook-tree-notes collapsed"))
  ]

/-- Build notebook page data for Stencil -/
def notebookPageData (ctx : Context) (notebooks : List NotebookView)
    (notesMap : List (Nat × List NoteView)) (selectedNote : Option NoteView) : Stencil.Value :=
  let selectedNoteId := selectedNote.map (·.id)
  let notebooksWithNotes := notebooks.map fun nb =>
    let notes := notesMap.find? (fun p => p.1 == nb.id) |>.map (·.2) |>.getD []
    notebookWithNotesToValue nb notes selectedNoteId
  let selectedNoteValue := match selectedNote with
    | some note => noteToValue note selectedNoteId
    | none => .null
  .object #[
    ("hasNotebooks", .bool (!notebooks.isEmpty)),
    ("notebooks", .array notebooksWithNotes.toArray),
    ("hasSelectedNote", .bool selectedNote.isSome),
    ("selectedNote", selectedNoteValue),
    ("csrfToken", .string ctx.csrfToken)
  ]

/-! ## Pages -/

-- Main notebook page (no note selected)
view notebookPage "/notebook" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let notebooks := getNotebooks ctx
  let notesMap := getAllNotesGrouped ctx notebooks
  let data := pageContext ctx "Notebook" PageId.notebook (notebookPageData ctx notebooks notesMap none)
  Loom.Stencil.ActionM.renderWithLayout "app" "notebook/index" data

-- New notebook form (modal) - MUST come before /notebook/:id
view newNotebookForm "/notebook/new" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  Loom.Stencil.ActionM.render "notebook/new-notebook" (.object #[("csrfToken", .string ctx.csrfToken)])

-- View specific notebook (redirect to notebook page, notebooks expand via JS)
view notebookView "/notebook/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let notebooks := getNotebooks ctx
  let notesMap := getAllNotesGrouped ctx notebooks
  match getNotebook ctx id with
  | none => notFound "Notebook not found"
  | some _ =>
    let data := pageContext ctx "Notebook" PageId.notebook (notebookPageData ctx notebooks notesMap none)
    Loom.Stencil.ActionM.renderWithLayout "app" "notebook/index" data

-- View specific note
view noteView "/notebook/note/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let notebooks := getNotebooks ctx
  let notesMap := getAllNotesGrouped ctx notebooks
  match getNote ctx id with
  | none => notFound "Note not found"
  | some note =>
    let data := pageContext ctx s!"{note.title} - Notebook" PageId.notebook
      (notebookPageData ctx notebooks notesMap (some note))
    Loom.Stencil.ActionM.renderWithLayout "app" "notebook/index" data

-- Edit notebook form (modal)
view editNotebookForm "/notebook/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getNotebook ctx id with
  | none => notFound "Notebook not found"
  | some nb =>
    let data : Stencil.Value := .object #[
      ("id", .int (Int.ofNat id)),
      ("title", .string nb.title),
      ("csrfToken", .string ctx.csrfToken)
    ]
    Loom.Stencil.ActionM.render "notebook/edit-notebook" data

-- New note form (modal)
view newNoteForm "/notebook/:id/note/new" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let data : Stencil.Value := .object #[
    ("notebookId", .int (Int.ofNat id)),
    ("csrfToken", .string ctx.csrfToken)
  ]
  Loom.Stencil.ActionM.render "notebook/new-note" data

/-! ## Actions -/

-- Create notebook
action createNotebook "/notebook/create" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  if title.isEmpty then return ← badRequest "Title is required"
  match notebookGetCurrentUserEid ctx with
  | none => seeOther "/login"
  | some userEid =>
    let now ← notebookGetNowMs
    let (eid, _) ← withNewEntityAudit! fun eid => do
      let nb : DbNotebook := { id := eid.id.toNat, title := title, createdAt := now, user := userEid }
      DbNotebook.TxM.create eid nb
      audit "CREATE" "notebook" eid.id.toNat [("title", title)]
    let _ ← SSE.publishEvent "notebook" "notebook-created" (jsonStr! { title })
    seeOther s!"/notebook/{eid.id.toNat}"

-- Update notebook
action updateNotebook "/notebook/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  if title.isEmpty then return ← badRequest "Title is required"
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbNotebook.TxM.setTitle eid title
    audit "UPDATE" "notebook" id [("title", title)]
  let notebookId := id
  let _ ← SSE.publishEvent "notebook" "notebook-updated" (jsonStr! { notebookId, title })
  seeOther s!"/notebook/{id}"

-- Delete notebook
action deleteNotebook "/notebook/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  -- Delete all notes in this notebook first
  let notes := getNotesInNotebook ctx id
  for note in notes do
    let noteEid : EntityId := ⟨note.id⟩
    runAuditTx! do
      DbNote.TxM.delete noteEid
      audit "DELETE" "note" note.id [("notebook_id", toString id)]
  -- Delete the notebook
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbNotebook.TxM.delete eid
    audit "DELETE" "notebook" id []
  let notebookId := id
  let _ ← SSE.publishEvent "notebook" "notebook-deleted" (jsonStr! { notebookId })
  htmxRedirect "/notebook"

-- Create note
action createNote "/notebook/:id/note/create" POST [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  let content := ctx.paramD "content" ""
  if title.isEmpty then return ← badRequest "Title is required"
  match notebookGetCurrentUserEid ctx with
  | none => seeOther "/login"
  | some userEid =>
    let now ← notebookGetNowMs
    let nbEid : EntityId := ⟨id⟩
    let (noteEid, _) ← withNewEntityAudit! fun eid => do
      let note : DbNote := { id := eid.id.toNat, title := title, content := content,
                             notebook := nbEid, createdAt := now, updatedAt := now,
                             version := 1, user := userEid }
      DbNote.TxM.create eid note
      audit "CREATE" "note" eid.id.toNat [("title", title), ("notebook_id", toString id)]
    let notebookId := id
    let _ ← SSE.publishEvent "notebook" "note-created" (jsonStr! { notebookId, title })
    seeOther s!"/notebook/note/{noteEid.id.toNat}"

-- Update note with optimistic locking
action updateNote "/notebook/note/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  let content := ctx.paramD "content" ""
  let saveId := ctx.paramD "saveId" ""
  let clientVersion := (ctx.paramD "version" "0").toNat?.getD 0
  if title.isEmpty then return ← badRequest "Title is required"

  -- Get current note to check version
  match getNote ctx id with
  | none => notFound "Note not found"
  | some currentNote =>
    -- Check for version conflict
    if clientVersion != currentNote.version then
      -- Version mismatch - return conflict with current data
      let conflict := true
      let serverVersion := currentNote.version
      let serverTitle := currentNote.title
      let serverContent := currentNote.content
      json (jsonStr! { conflict, serverVersion, serverTitle, serverContent })
    else
      -- Version matches - proceed with update
      let now ← notebookGetNowMs
      let eid : EntityId := ⟨id⟩
      let newVersion := currentNote.version + 1
      runAuditTx! do
        DbNote.TxM.setTitle eid title
        DbNote.TxM.setContent eid content
        DbNote.TxM.setUpdatedAt eid now
        DbNote.TxM.setVersion eid newVersion
        audit "UPDATE" "note" id [("title", title), ("version", toString newVersion)]
      let noteId := id
      let version := newVersion
      let _ ← SSE.publishEvent "notebook" "note-updated" (jsonStr! { noteId, title, saveId, version })
      json (jsonStr! { noteId, version })

-- Delete note
action deleteNote "/notebook/note/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getNote ctx id with
  | none => htmxRedirect "/notebook"
  | some note =>
    let noteEid : EntityId := ⟨id⟩
    runAuditTx! do
      DbNote.TxM.delete noteEid
      audit "DELETE" "note" id []
    let noteId := id
    let notebookId := note.notebookId
    let _ ← SSE.publishEvent "notebook" "note-deleted" (jsonStr! { noteId, notebookId })
    htmxRedirect s!"/notebook/{note.notebookId}"

-- Upload image for rich text editor
action notebookUploadImage "/notebook/upload-image" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  match ctx.file "image" with
  | none => json "{\"error\": \"No file uploaded\"}"
  | some file =>
    -- Validate it's an image
    let contentType := file.contentType.getD "application/octet-stream"
    if !contentType.startsWith "image/" then
      json "{\"error\": \"Only images are allowed\"}"
    else if file.content.size > Upload.maxFileSize then
      json "{\"error\": \"File too large\"}"
    else
      let storedPath ← Upload.storeFile file.content (file.filename.getD "image")
      let url := s!"/uploads/{storedPath}"
      json s!"\{\"url\": \"{url}\"}"

end HomebaseApp.Pages
