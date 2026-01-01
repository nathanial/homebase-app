/-
  HomebaseApp.Pages.Gallery - Photo and file gallery
-/
import Scribe
import Loom
import Loom.SSE
import Loom.Stencil
import Stencil
import Ledger
import Citadel
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
open HomebaseApp.Upload
open HomebaseApp.StencilHelpers

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

/-! ## Stencil Value Helpers -/

/-- Format file size for display -/
def galleryFormatFileSize (bytes : Nat) : String :=
  if bytes >= 1024 * 1024 then
    s!"{bytes / (1024 * 1024)} MB"
  else if bytes >= 1024 then
    s!"{bytes / 1024} KB"
  else
    s!"{bytes} B"

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

/-- Get file extension from filename -/
def getExtension' (fileName : String) : String :=
  match fileName.splitOn "." with
  | [] => ""
  | [_] => ""
  | parts => parts.getLast!.toUpper

/-- Convert a GalleryItem to Stencil.Value -/
def galleryItemToValue (item : GalleryItem) (now : Nat) : Stencil.Value :=
  let displayTitle := if item.title.isEmpty then item.fileName else item.title
  .object #[
    ("id", .int (Int.ofNat item.id)),
    ("title", .string item.title),
    ("description", .string item.description),
    ("fileName", .string item.fileName),
    ("url", .string item.url),
    ("mimeType", .string item.mimeType),
    ("isImage", .bool item.isImage),
    ("extension", .string (getExtension' item.fileName)),
    ("displayTitle", .string displayTitle),
    ("formattedSize", .string (galleryFormatFileSize item.fileSize)),
    ("relativeTime", .string (galleryFormatRelativeTime item.uploadedAt now)),
    ("hasDescription", .bool (!item.description.isEmpty))
  ]

/-- Convert a list of gallery items to Stencil.Value -/
def galleryItemsToValue (items : List GalleryItem) (now : Nat) : Stencil.Value :=
  .array (items.map (galleryItemToValue · now)).toArray

/-! ## Helpers -/

/-- Check if a MIME type is an image -/
def isImageType (mimeType : String) : Bool :=
  mimeType.startsWith "image/"

/-- Get current time in milliseconds -/
def galleryGetNowMs : IO Nat := IO.monoMsNow

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

/-! ## Pages -/

-- Main gallery page
view galleryPage "/gallery" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let filter := ctx.paramD "filter" "all"
  let items := getGalleryItemsFiltered ctx filter
  let now ← galleryGetNowMs
  let data := pageContext ctx "Gallery" PageId.gallery
    (.object #[
      ("items", galleryItemsToValue items now),
      ("hasItems", .bool (!items.isEmpty)),
      ("itemCount", .int (Int.ofNat items.length)),
      ("filterAll", .bool (filter == "all")),
      ("filterImages", .bool (filter == "images")),
      ("filterDocuments", .bool (filter == "documents"))
    ])
  Loom.Stencil.ActionM.renderWithLayout "app" "gallery/index" data

-- Gallery grid refresh (for HTMX)
view galleryGrid "/gallery/grid" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let filter := ctx.paramD "filter" "all"
  let items := getGalleryItemsFiltered ctx filter
  let now ← galleryGetNowMs
  let data : Stencil.Value := .object #[
    ("items", galleryItemsToValue items now),
    ("hasItems", .bool (!items.isEmpty))
  ]
  Loom.Stencil.ActionM.render "gallery/grid" data

-- Item detail / lightbox
view galleryItemView "/gallery/item/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getGalleryItem ctx id with
  | none => notFound "Item not found"
  | some item =>
    let now ← galleryGetNowMs
    let data := galleryItemToValue item now
    Loom.Stencil.ActionM.render "gallery/show" data

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
    let _ ← SSE.publishEvent "gallery" "item-uploaded" (jsonStr! { fileName, mimeType })
    redirect "/gallery"

-- Edit item form
view galleryEditForm "/gallery/item/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getGalleryItem ctx id with
  | none => notFound "Item not found"
  | some item =>
    let now ← galleryGetNowMs
    let data := mergeContext (galleryItemToValue item now)
      (.object #[("csrfToken", .string ctx.csrfToken)])
    Loom.Stencil.ActionM.render "gallery/edit" data

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
  let itemId := id
  let _ ← SSE.publishEvent "gallery" "item-updated" (jsonStr! { itemId, title })
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
    let itemId := id
    let fileName := item.fileName
    let _ ← SSE.publishEvent "gallery" "item-deleted" (jsonStr! { itemId, fileName })
    redirect "/gallery"

end HomebaseApp.Pages
