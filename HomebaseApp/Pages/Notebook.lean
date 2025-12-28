/-
  HomebaseApp.Pages.Notebook - Markdown notes with notebook organization
-/
import Scribe
import Loom
import Loom.SSE
import Loom.Htmx
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
               notebookId := nbId, createdAt := note.createdAt, updatedAt := note.updatedAt }
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
             updatedAt := note.updatedAt }
    | none => none
  | none => none

/-! ## View Helpers -/

/-- Attribute to clear modal after form submission -/
def notebookModalClearAttr : Attr :=
  ⟨"hx-on::after-request", "document.getElementById('modal-container').innerHTML = ''"⟩

/-- Render notebook list sidebar -/
def renderNotebookList (notebooks : List NotebookView) (selectedId : Option Nat) : HtmlM Unit := do
  div [class_ "notebook-sidebar"] do
    div [class_ "notebook-sidebar-header"] do
      h3 [] (text "Notebooks")
      button [hx_get "/notebook/new", hx_target "#modal-container",
              hx_swap "innerHTML", class_ "btn btn-sm btn-primary"] (text "+")
    div [class_ "notebook-list"] do
      if notebooks.isEmpty then
        p [class_ "notebook-empty-hint"] (text "No notebooks yet")
      else
        for nb in notebooks do
          let isSelected := selectedId == some nb.id
          a [href_ s!"/notebook/{nb.id}",
             class_ (if isSelected then "notebook-item selected" else "notebook-item")] do
            span [class_ "notebook-item-title"] (text nb.title)
            span [class_ "notebook-item-count"] (text (toString nb.noteCount))

/-- Render notes list -/
def renderNotesList (notes : List NoteView) (now : Nat) (selectedId : Option Nat) : HtmlM Unit := do
  div [class_ "notebook-notes-list"] do
    if notes.isEmpty then
      div [class_ "notebook-notes-empty"] do
        p [] (text "No notes in this notebook")
        p [class_ "text-muted"] (text "Create one to get started!")
    else
      for note in notes do
        let isSelected := selectedId == some note.id
        a [href_ s!"/notebook/note/{note.id}",
           class_ (if isSelected then "notebook-note-item selected" else "notebook-note-item")] do
          h4 [class_ "notebook-note-title"] (text note.title)
          p [class_ "notebook-note-preview"] (text (note.content.take 100))
          span [class_ "notebook-note-time"] (text (notebookFormatRelativeTime note.updatedAt now))

/-- Render note editor -/
def renderNoteEditor (note : NoteView) (ctx : Context) : HtmlM Unit := do
  div [class_ "notebook-editor"] do
    form [attr_ "action" s!"/notebook/note/{note.id}", attr_ "method" "PUT"] do
      csrfField ctx.csrfToken
      div [class_ "notebook-editor-header"] do
        input [type_ "text", name_ "title", id_ "note-title", value_ note.title,
               class_ "notebook-title-input", placeholder_ "Note title", required_]
        div [class_ "notebook-editor-actions"] do
          span [id_ "save-status", class_ "notebook-save-status"] (pure ())
          button [type_ "button", hx_delete s!"/notebook/note/{note.id}",
                  hx_confirm "Delete this note?", hx_swap "none",
                  class_ "btn btn-danger btn-sm"] (text "Delete")
      textarea [name_ "content", id_ "note-content", class_ "notebook-content-input",
                placeholder_ "Write your note in markdown...", rows_ 20] note.content

/-- Render empty state when no notebook selected -/
def notebookRenderEmptyState : HtmlM Unit := do
  div [class_ "notebook-empty-state"] do
    div [class_ "notebook-empty-icon"] (text "📓")
    h2 [] (text "Select a Notebook")
    p [] (text "Choose a notebook from the sidebar or create a new one")

/-- Main notebook page content -/
def notebookPageContent (ctx : Context) (notebooks : List NotebookView) (selectedNotebook : Option NotebookView)
    (notes : List NoteView) (selectedNote : Option NoteView) (now : Nat) : HtmlM Unit := do
  div [class_ "notebook-container"] do
    -- Sidebar with notebooks
    renderNotebookList notebooks (selectedNotebook.map (·.id))
    -- Main content area
    div [class_ "notebook-main"] do
      match selectedNotebook with
      | none => notebookRenderEmptyState
      | some nb =>
        div [class_ "notebook-content"] do
          -- Notebook header
          div [class_ "notebook-header"] do
            h2 [] (text nb.title)
            div [class_ "notebook-header-actions"] do
              button [hx_get s!"/notebook/{nb.id}/note/new", hx_target "#modal-container",
                      hx_swap "innerHTML", class_ "btn btn-primary btn-sm"] (text "+ New Note")
              button [hx_get s!"/notebook/{nb.id}/edit", hx_target "#modal-container",
                      hx_swap "innerHTML", class_ "btn btn-secondary btn-sm"] (text "Edit")
              button [hx_delete s!"/notebook/{nb.id}", hx_confirm "Delete this notebook and all its notes?",
                      hx_swap "none", class_ "btn btn-danger btn-sm"] (text "Delete")
          -- Split view: notes list + editor
          div [class_ "notebook-split"] do
            renderNotesList notes now (selectedNote.map (·.id))
            match selectedNote with
            | some note => renderNoteEditor note ctx
            | none =>
              div [class_ "notebook-no-note"] do
                p [] (text "Select a note to view or edit")
    -- Modal container
    div [id_ "modal-container"] (pure ())
    -- SSE script
    script [src_ "/js/notebook.js"]

/-! ## Pages -/

-- Main notebook page (no notebook selected)
view notebookPage "/notebook" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let notebooks := getNotebooks ctx
  let now ← notebookGetNowMs
  html (Shared.render ctx "Notebook - Homebase" "/notebook"
    (notebookPageContent ctx notebooks none [] none now))

-- New notebook form (modal) - MUST come before /notebook/:id
view newNotebookForm "/notebook/new" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  html (HtmlM.render do
    div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
      div [class_ "modal-container modal-sm"] do
        h3 [class_ "modal-title"] (text "New Notebook")
        form [hx_post "/notebook/create", hx_swap "none", notebookModalClearAttr] do
          csrfField ctx.csrfToken
          div [class_ "form-stack"] do
            div [class_ "form-group"] do
              label [for_ "title", class_ "form-label"] (text "Title")
              input [type_ "text", name_ "title", id_ "title",
                     class_ "form-input", required_, autofocus_]
            div [class_ "form-actions"] do
              button [type_ "button", class_ "btn btn-secondary",
                      attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
              button [type_ "submit", class_ "btn btn-primary"] (text "Create"))

-- View specific notebook - MUST come after /notebook/new
view notebookView "/notebook/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let notebooks := getNotebooks ctx
  let now ← notebookGetNowMs
  match getNotebook ctx id with
  | none => notFound "Notebook not found"
  | some nb =>
    let notes := getNotesInNotebook ctx id
    html (Shared.render ctx s!"{nb.title} - Notebook" "/notebook"
      (notebookPageContent ctx notebooks (some nb) notes none now))

-- View specific note
view noteView "/notebook/note/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let notebooks := getNotebooks ctx
  let now ← notebookGetNowMs
  match getNote ctx id with
  | none => notFound "Note not found"
  | some note =>
    let nb := getNotebook ctx note.notebookId
    let notes := getNotesInNotebook ctx note.notebookId
    html (Shared.render ctx s!"{note.title} - Notebook" "/notebook"
      (notebookPageContent ctx notebooks nb notes (some note) now))

-- Edit notebook form (modal)
view editNotebookForm "/notebook/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getNotebook ctx id with
  | none => notFound "Notebook not found"
  | some nb =>
    html (HtmlM.render do
      div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
        div [class_ "modal-container modal-sm"] do
          h3 [class_ "modal-title"] (text "Edit Notebook")
          form [hx_put s!"/notebook/{id}", hx_swap "none", notebookModalClearAttr] do
            csrfField ctx.csrfToken
            div [class_ "form-stack"] do
              div [class_ "form-group"] do
                label [for_ "title", class_ "form-label"] (text "Title")
                input [type_ "text", name_ "title", id_ "title",
                       value_ nb.title, class_ "form-input", required_]
              div [class_ "form-actions"] do
                button [type_ "button", class_ "btn btn-secondary",
                        attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
                button [type_ "submit", class_ "btn btn-primary"] (text "Save"))

-- New note form (modal)
view newNoteForm "/notebook/:id/note/new" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  html (HtmlM.render do
    div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
      div [class_ "modal-container modal-md"] do
        h3 [class_ "modal-title"] (text "New Note")
        form [hx_post s!"/notebook/{id}/note/create", hx_swap "none", notebookModalClearAttr] do
          csrfField ctx.csrfToken
          div [class_ "form-stack"] do
            div [class_ "form-group"] do
              label [for_ "title", class_ "form-label"] (text "Title")
              input [type_ "text", name_ "title", id_ "title",
                     class_ "form-input", required_, autofocus_]
            div [class_ "form-group"] do
              label [for_ "content", class_ "form-label"] (text "Content")
              textarea [name_ "content", id_ "content", class_ "form-textarea", rows_ 8,
                        placeholder_ "Write your note in markdown..."] ""
            div [class_ "form-actions"] do
              button [type_ "button", class_ "btn btn-secondary",
                      attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
              button [type_ "submit", class_ "btn btn-primary"] (text "Create"))

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
                             notebook := nbEid, createdAt := now, updatedAt := now, user := userEid }
      DbNote.TxM.create eid note
      audit "CREATE" "note" eid.id.toNat [("title", title), ("notebook_id", toString id)]
    let notebookId := id
    let _ ← SSE.publishEvent "notebook" "note-created" (jsonStr! { notebookId, title })
    seeOther s!"/notebook/note/{noteEid.id.toNat}"

-- Update note
action updateNote "/notebook/note/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  let content := ctx.paramD "content" ""
  let saveId := ctx.paramD "saveId" ""
  if title.isEmpty then return ← badRequest "Title is required"
  let now ← notebookGetNowMs
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbNote.TxM.setTitle eid title
    DbNote.TxM.setContent eid content
    DbNote.TxM.setUpdatedAt eid now
    audit "UPDATE" "note" id [("title", title)]
  let noteId := id
  let _ ← SSE.publishEvent "notebook" "note-updated" (jsonStr! { noteId, title, saveId })
  seeOther s!"/notebook/note/{id}"

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

end HomebaseApp.Pages
