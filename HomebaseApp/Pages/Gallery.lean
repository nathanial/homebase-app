/-
  HomebaseApp.Pages.Gallery - Photo and file gallery
-/
import Scribe
import Loom
import Ledger
import Citadel
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Helpers
import HomebaseApp.Middleware
import HomebaseApp.Upload

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
open HomebaseApp.Upload

/-! ## Data Structures -/

/-- View model for a gallery item -/
structure GalleryItem where
  id : Nat
  title : String
  description : String
  fileName : String
  storedPath : String
  mimeType : String
  fileSize : Nat
  uploadedAt : Nat
  url : String            -- Computed: /uploads/{storedPath}
  isImage : Bool          -- Computed: is this an image?
  deriving Inhabited

/-! ## Helpers -/

/-- Check if a MIME type is an image -/
def isImageType (mimeType : String) : Bool :=
  mimeType.startsWith "image/"

/-- Format file size for display -/
def galleryFormatFileSize (bytes : Nat) : String :=
  if bytes >= 1024 * 1024 then
    s!"{bytes / (1024 * 1024)} MB"
  else if bytes >= 1024 then
    s!"{bytes / 1024} KB"
  else
    s!"{bytes} B"

/-- Get current time in milliseconds -/
def galleryGetNowMs : IO Nat := IO.monoMsNow

/-- Format relative time -/
def galleryFormatRelativeTime (timestamp now : Nat) : String :=
  let diffMs := now - timestamp
  let diffSecs := diffMs / 1000
  let diffMins := diffSecs / 60
  let diffHours := diffMins / 60
  let diffDays := diffHours / 24
  if diffDays > 0 then s!"{diffDays}d ago"
  else if diffHours > 0 then s!"{diffHours}h ago"
  else if diffMins > 0 then s!"{diffMins}m ago"
  else "just now"

/-! ## Database Helpers -/

/-- Get current user's EntityId -/
def galleryGetCurrentUserEid (ctx : Context) : Option EntityId :=
  match currentUserId ctx with
  | some idStr => idStr.toNat?.map fun n => ⟨n⟩
  | none => none

/-- Get all gallery items for current user -/
def getGalleryItems (ctx : Context) : List GalleryItem :=
  match ctx.database, galleryGetCurrentUserEid ctx with
  | some db, some userEid =>
    let itemIds := db.findByAttrValue DbGalleryItem.attr_user (.ref userEid)
    let items := itemIds.filterMap fun itemId =>
      match DbGalleryItem.pull db itemId with
      | some item =>
        let isImage := isImageType item.mimeType
        some { id := item.id, title := item.title, description := item.description,
               fileName := item.fileName, storedPath := item.storedPath,
               mimeType := item.mimeType, fileSize := item.fileSize,
               uploadedAt := item.uploadedAt, url := s!"/uploads/{item.storedPath}",
               isImage := isImage }
      | none => none
    items.toArray.qsort (fun a b => a.uploadedAt > b.uploadedAt) |>.toList  -- newest first
  | _, _ => []

/-- Get gallery items filtered by type -/
def getGalleryItemsFiltered (ctx : Context) (filter : String) : List GalleryItem :=
  let items := getGalleryItems ctx
  match filter with
  | "images" => items.filter (·.isImage)
  | "documents" => items.filter (!·.isImage)
  | _ => items

/-- Get a single gallery item by ID -/
def getGalleryItem (ctx : Context) (itemId : Nat) : Option GalleryItem :=
  match ctx.database with
  | some db =>
    let eid : EntityId := ⟨itemId⟩
    match DbGalleryItem.pull db eid with
    | some item =>
      let isImage := isImageType item.mimeType
      some { id := item.id, title := item.title, description := item.description,
             fileName := item.fileName, storedPath := item.storedPath,
             mimeType := item.mimeType, fileSize := item.fileSize,
             uploadedAt := item.uploadedAt, url := s!"/uploads/{item.storedPath}",
             isImage := isImage }
    | none => none
  | none => none

/-! ## View Helpers -/

/-- Attribute to clear modal after form submission -/
def galleryModalClearAttr : Attr :=
  ⟨"hx-on::after-request", "document.getElementById('modal-container').innerHTML = ''"⟩

/-- Render a single gallery item in grid view -/
def renderGalleryItem (item : GalleryItem) (now : Nat) : HtmlM Unit := do
  div [id_ s!"item-{item.id}", class_ "gallery-item",
       hx_get s!"/gallery/item/{item.id}", hx_target "#modal-container", hx_swap "innerHTML"] do
    if item.isImage then
      div [class_ "gallery-thumbnail"] do
        img [src_ item.url, alt_ item.title, loading_ "lazy"]
    else
      div [class_ "gallery-thumbnail gallery-file"] do
        span [class_ "gallery-file-icon"] (text "📄")
        span [class_ "gallery-file-ext"] (text (getExtension item.fileName))
    div [class_ "gallery-item-info"] do
      p [class_ "gallery-item-title"] (text (if item.title.isEmpty then item.fileName else item.title))
      p [class_ "gallery-item-meta"] (text s!"{galleryFormatFileSize item.fileSize} · {galleryFormatRelativeTime item.uploadedAt now}")

/-- Render the gallery grid -/
def renderGalleryGrid (items : List GalleryItem) (now : Nat) : HtmlM Unit := do
  if items.isEmpty then
    div [class_ "gallery-empty"] do
      div [class_ "gallery-empty-icon"] (text "🖼️")
      p [] (text "No items in your gallery yet.")
      p [class_ "text-muted"] (text "Upload some photos or files to get started!")
  else
    div [class_ "gallery-grid"] do
      for item in items do renderGalleryItem item now

/-- Render the upload zone -/
def galleryRenderUploadZone (ctx : Context) : HtmlM Unit := do
  div [id_ "upload-zone", class_ "gallery-upload-zone"] do
    form [id_ "upload-form", hx_post "/gallery/upload", hx_encoding "multipart/form-data",
          hx_swap "none",
          attr_ "hx-on::after-request" "if(event.detail.successful) window.location.reload()"] do
      csrfField ctx.csrfToken
      div [class_ "gallery-upload-content"] do
        span [class_ "gallery-upload-icon"] (text "📤")
        p [class_ "gallery-upload-text"] (text "Drop files here or click to upload")
        input [type_ "file", name_ "file", id_ "file-input", class_ "gallery-file-input",
               attr_ "accept" "image/*,.pdf,.txt",
               attr_ "onchange" "this.form.requestSubmit()"]

/-- Render filter tabs -/
def renderFilterTabs (currentFilter : String) : HtmlM Unit := do
  div [class_ "gallery-filters"] do
    let isActive (f : String) : String := if f == currentFilter then " active" else ""
    a [href_ "/gallery", class_ s!"gallery-filter-tab{isActive "all"}"] (text "All")
    a [href_ "/gallery?filter=images", class_ s!"gallery-filter-tab{isActive "images"}"] (text "Images")
    a [href_ "/gallery?filter=documents", class_ s!"gallery-filter-tab{isActive "documents"}"] (text "Documents")

/-- Main gallery page content -/
def galleryPageContent (ctx : Context) (items : List GalleryItem) (filter : String) (now : Nat) : HtmlM Unit := do
  div [class_ "gallery-container"] do
    -- Header
    div [class_ "gallery-header"] do
      h1 [] (text "Gallery")
      span [class_ "gallery-count"] (text s!"{items.length} items")
    -- Upload zone
    galleryRenderUploadZone ctx
    -- Filters
    renderFilterTabs filter
    -- Grid
    div [id_ "gallery-items"] do
      renderGalleryGrid items now
    -- Modal container
    div [id_ "modal-container"] (pure ())
    -- Drag & drop script
    script [type_ "text/javascript"] "(function() { const zone = document.getElementById('upload-zone'); const input = document.getElementById('file-input'); if (!zone || !input) return; ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(event => { zone.addEventListener(event, e => { e.preventDefault(); e.stopPropagation(); }); }); ['dragenter', 'dragover'].forEach(event => { zone.addEventListener(event, () => zone.classList.add('dragover')); }); ['dragleave', 'drop'].forEach(event => { zone.addEventListener(event, () => zone.classList.remove('dragover')); }); zone.addEventListener('drop', e => { const files = e.dataTransfer.files; if (files.length > 0) { input.files = files; document.getElementById('upload-form').requestSubmit(); } }); zone.addEventListener('click', () => input.click()); })();"

/-- Render lightbox modal for an item -/
def renderLightbox (item : GalleryItem) (now : Nat) : HtmlM Unit := do
  div [class_ "modal-overlay gallery-lightbox",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "gallery-lightbox-content"] do
      -- Close button
      button [class_ "gallery-lightbox-close",
              attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "x")
      -- Image/file preview
      if item.isImage then
        div [class_ "gallery-lightbox-image"] do
          img [src_ item.url, alt_ item.title]
      else
        div [class_ "gallery-lightbox-file"] do
          span [class_ "gallery-file-icon-large"] (text "📄")
          p [] (text item.fileName)
      -- Info panel
      div [class_ "gallery-lightbox-info"] do
        h3 [] (text (if item.title.isEmpty then item.fileName else item.title))
        if !item.description.isEmpty then
          p [class_ "gallery-lightbox-description"] (text item.description)
        div [class_ "gallery-lightbox-meta"] do
          p [] (text s!"Size: {galleryFormatFileSize item.fileSize}")
          p [] (text s!"Type: {item.mimeType}")
          p [] (text s!"Uploaded: {galleryFormatRelativeTime item.uploadedAt now}")
        -- Actions
        div [class_ "gallery-lightbox-actions"] do
          a [href_ item.url, download_ item.fileName, class_ "btn btn-secondary"] (text "Download")
          button [hx_get s!"/gallery/item/{item.id}/edit", hx_target "#modal-container",
                  hx_swap "innerHTML", class_ "btn btn-secondary"] (text "Edit")
          button [hx_delete s!"/gallery/item/{item.id}", hx_swap "none",
                  hx_confirm "Delete this item?",
                  class_ "btn btn-danger"] (text "Delete")

/-! ## Pages -/

-- Main gallery page
view galleryPage "/gallery" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let filter := ctx.paramD "filter" "all"
  let items := getGalleryItemsFiltered ctx filter
  let now ← galleryGetNowMs
  html (Shared.render ctx "Gallery - Homebase" "/gallery" (galleryPageContent ctx items filter now))

-- Gallery grid refresh (for HTMX)
view galleryGrid "/gallery/grid" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let filter := ctx.paramD "filter" "all"
  let items := getGalleryItemsFiltered ctx filter
  let now ← galleryGetNowMs
  html (HtmlM.render (renderGalleryGrid items now))

-- Item detail / lightbox
view galleryItemView "/gallery/item/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getGalleryItem ctx id with
  | none => notFound "Item not found"
  | some item =>
    let now ← galleryGetNowMs
    html (HtmlM.render (renderLightbox item now))

-- Upload file
action galleryUpload "/gallery/upload" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  match ctx.file "file", galleryGetCurrentUserEid ctx with
  | none, _ => redirect "/gallery"
  | _, none => redirect "/login"
  | some file, some userEid =>
    if file.content.size > maxFileSize then
      let ctx := ctx.withFlash fun f => f.set "error" "File too large (max 10MB)"
      return ← redirect "/gallery"
    let mimeType := file.contentType.getD "application/octet-stream"
    if !isAllowedType mimeType then
      let ctx := ctx.withFlash fun f => f.set "error" "File type not allowed"
      return ← redirect "/gallery"
    let storedPath ← storeFile file.content (file.filename.getD "upload")
    let now ← galleryGetNowMs
    let fileName := file.filename.getD "upload"
    let (_, _) ← withNewEntityAudit! fun eid => do
      let item : DbGalleryItem := {
        id := eid.id.toNat
        title := ""  -- User can set title via edit
        description := ""
        fileName := fileName
        storedPath := storedPath
        mimeType := mimeType
        fileSize := file.content.size
        uploadedAt := now
        user := userEid
      }
      DbGalleryItem.TxM.create eid item
      audit "CREATE" "gallery-item" eid.id.toNat [("file_name", fileName)]
    redirect "/gallery"

-- Edit item form
view galleryEditForm "/gallery/item/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getGalleryItem ctx id with
  | none => notFound "Item not found"
  | some item =>
    html (HtmlM.render do
      div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
        div [class_ "modal-container modal-md"] do
          h3 [class_ "modal-title"] (text "Edit Item")
          form [hx_put s!"/gallery/item/{id}", hx_swap "none", galleryModalClearAttr] do
            csrfField ctx.csrfToken
            div [class_ "form-stack"] do
              div [class_ "form-group"] do
                label [for_ "title", class_ "form-label"] (text "Title")
                input [type_ "text", name_ "title", id_ "title",
                       value_ item.title, placeholder_ item.fileName,
                       class_ "form-input"]
              div [class_ "form-group"] do
                label [for_ "description", class_ "form-label"] (text "Description")
                textarea [name_ "description", id_ "description",
                          class_ "form-textarea", rows_ 3] item.description
              div [class_ "form-actions"] do
                button [type_ "button", class_ "btn btn-secondary",
                        attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
                button [type_ "submit", class_ "btn btn-primary"] (text "Save Changes"))

-- Update item
action galleryUpdateItem "/gallery/item/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  let description := ctx.paramD "description" ""
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbGalleryItem.TxM.setTitle eid title
    DbGalleryItem.TxM.setDescription eid description
    audit "UPDATE" "gallery-item" id [("title", title)]
  redirect "/gallery"

-- Delete item
action galleryDeleteItem "/gallery/item/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getGalleryItem ctx id with
  | none => redirect "/gallery"
  | some item =>
    -- Delete the file
    let _ ← Upload.deleteFile item.storedPath
    -- Delete the database record
    let eid : EntityId := ⟨id⟩
    runAuditTx! do
      DbGalleryItem.TxM.delete eid
      audit "DELETE" "gallery-item" id [("file_name", item.fileName)]
    redirect "/gallery"

end HomebaseApp.Pages
