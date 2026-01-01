/-
  HomebaseApp.Pages.News - Link aggregator with read/save tracking
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

/-- News category options -/
def newsCategories : List String :=
  ["Tech", "Business", "Science", "Health", "Sports", "Entertainment", "General"]

/-! ## View Models -/

/-- View model for a news item -/
structure NewsItemView where
  id : Nat
  title : String
  url : String
  description : String
  source : String
  category : String
  isRead : Bool
  isSaved : Bool
  addedAt : Nat
  deriving Inhabited

/-! ## Stencil Value Helpers -/

/-- Format relative time -/
def newsFormatRelativeTime (timestamp now : Nat) : String :=
  let diffMs := now - timestamp
  let diffSecs := diffMs / 1000
  let diffMins := diffSecs / 60
  let diffHours := diffMins / 60
  let diffDays := diffHours / 24
  if diffDays > 0 then s!"{diffDays}d ago"
  else if diffHours > 0 then s!"{diffHours}h ago"
  else if diffMins > 0 then s!"{diffMins}m ago"
  else "just now"

/-- Extract domain from URL -/
def newsExtractDomain (url : String) : String :=
  let parts := url.splitOn "://"
  match parts with
  | [_, rest] =>
    let domainParts := rest.splitOn "/"
    match domainParts.head? with
    | some domain => domain.splitOn "www." |>.getLast!
    | none => ""
  | _ => ""

/-- Convert a NewsItemView to Stencil.Value -/
def newsItemToValue (item : NewsItemView) (now : Nat) : Stencil.Value :=
  let displaySource := if item.source.isEmpty then newsExtractDomain item.url else item.source
  .object #[
    ("id", .int (Int.ofNat item.id)),
    ("title", .string item.title),
    ("url", .string item.url),
    ("description", .string item.description),
    ("shortDescription", .string (item.description.take 200)),
    ("source", .string item.source),
    ("displaySource", .string displaySource),
    ("category", .string item.category),
    ("isRead", .bool item.isRead),
    ("isSaved", .bool item.isSaved),
    ("hasDescription", .bool (!item.description.isEmpty)),
    ("relativeTime", .string (newsFormatRelativeTime item.addedAt now)),
    -- Category flags for edit form
    ("isTech", .bool (item.category == "Tech")),
    ("isBusiness", .bool (item.category == "Business")),
    ("isScience", .bool (item.category == "Science")),
    ("isHealth", .bool (item.category == "Health")),
    ("isSports", .bool (item.category == "Sports")),
    ("isEntertainment", .bool (item.category == "Entertainment")),
    ("isGeneral", .bool (item.category == "General"))
  ]

/-- Convert a list of news items to Stencil.Value -/
def newsItemsToValue (items : List NewsItemView) (now : Nat) : Stencil.Value :=
  .array (items.map (newsItemToValue · now)).toArray

/-! ## Helpers -/

/-- Get current time in milliseconds -/
def newsGetNowMs : IO Nat := do
  let output ← IO.Process.output { cmd := "date", args := #["+%s"] }
  let seconds := output.stdout.trim.toNat?.getD 0
  return seconds * 1000

/-- Get current user's EntityId -/
def newsGetCurrentUserEid (ctx : Context) : Option EntityId :=
  match currentUserId ctx with
  | some idStr => idStr.toNat?.map fun n => ⟨n⟩
  | none => none

/-! ## Database Helpers -/

/-- Get all news items for current user -/
def getNewsItems (ctx : Context) : List NewsItemView :=
  match ctx.database, newsGetCurrentUserEid ctx with
  | some db, some userEid =>
    let itemIds := db.findByAttrValue DbNewsItem.attr_user (.ref userEid)
    let items := itemIds.filterMap fun itemId =>
      match DbNewsItem.pull db itemId with
      | some item =>
        some { id := item.id, title := item.title, url := item.url,
               description := item.description, source := item.source,
               category := item.category, isRead := item.isRead,
               isSaved := item.isSaved, addedAt := item.addedAt }
      | none => none
    items.toArray.qsort (fun a b => a.addedAt > b.addedAt) |>.toList  -- newest first
  | _, _ => []

/-- Get news items filtered -/
def getNewsItemsFiltered (ctx : Context) (filter : String) : List NewsItemView :=
  let items := getNewsItems ctx
  match filter with
  | "unread" => items.filter (!·.isRead)
  | "saved" => items.filter (·.isSaved)
  | "all" => items
  | cat => items.filter (·.category == cat)

/-- Get a single news item by ID -/
def getNewsItem (ctx : Context) (itemId : Nat) : Option NewsItemView :=
  match ctx.database with
  | some db =>
    let eid : EntityId := ⟨itemId⟩
    match DbNewsItem.pull db eid with
    | some item =>
      some { id := item.id, title := item.title, url := item.url,
             description := item.description, source := item.source,
             category := item.category, isRead := item.isRead,
             isSaved := item.isSaved, addedAt := item.addedAt }
    | none => none
  | none => none

/-! ## Pages -/

-- Main news page
view newsPage "/news" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let filter := ctx.paramD "filter" "all"
  let now ← newsGetNowMs
  let allItems := getNewsItems ctx
  let items := getNewsItemsFiltered ctx filter
  let unreadCount := allItems.filter (!·.isRead) |>.length
  let savedCount := allItems.filter (·.isSaved) |>.length
  let data := pageContext ctx "News" PageId.news
    (.object #[
      ("items", newsItemsToValue items now),
      ("hasItems", .bool (!items.isEmpty)),
      ("unreadCount", .int (Int.ofNat unreadCount)),
      ("savedCount", .int (Int.ofNat savedCount)),
      ("filterAll", .bool (filter == "all")),
      ("filterUnread", .bool (filter == "unread")),
      ("filterSaved", .bool (filter == "saved")),
      ("filterTech", .bool (filter == "Tech")),
      ("filterBusiness", .bool (filter == "Business")),
      ("filterScience", .bool (filter == "Science")),
      ("filterHealth", .bool (filter == "Health")),
      ("filterSports", .bool (filter == "Sports")),
      ("filterEntertainment", .bool (filter == "Entertainment")),
      ("filterGeneral", .bool (filter == "General"))
    ])
  Loom.Stencil.ActionM.renderWithLayout "app" "news/index" data

-- Add link form (modal)
view newsAddForm "/news/add" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let data : Stencil.Value := .object #[("csrfToken", .string ctx.csrfToken)]
  Loom.Stencil.ActionM.render "news/add" data

-- Edit item form (modal)
view newsEditForm "/news/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getNewsItem ctx id with
  | none => notFound "Item not found"
  | some item =>
    let now ← newsGetNowMs
    let data := mergeContext (newsItemToValue item now)
      (.object #[("csrfToken", .string ctx.csrfToken)])
    Loom.Stencil.ActionM.render "news/edit" data

/-! ## Actions -/

-- Create news item
action newsCreate "/news/create" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let url := ctx.paramD "url" ""
  let title := ctx.paramD "title" ""
  let description := ctx.paramD "description" ""
  let source := ctx.paramD "source" ""
  let category := ctx.paramD "category" "General"
  if url.isEmpty || title.isEmpty then return ← badRequest "URL and title are required"
  match newsGetCurrentUserEid ctx with
  | none => redirect "/login"
  | some userEid =>
    let now ← newsGetNowMs
    let (_, _) ← withNewEntityAudit! fun eid => do
      let item : DbNewsItem := {
        id := eid.id.toNat, title := title, url := url,
        description := description, source := source, category := category,
        isRead := false, isSaved := false, addedAt := now, user := userEid
      }
      DbNewsItem.TxM.create eid item
      audit "CREATE" "news-item" eid.id.toNat [("title", title), ("url", url)]
    let _ ← SSE.publishEvent "news" "item-added" (jsonStr! { title, url })
    redirect "/news"

-- Update news item
action newsUpdate "/news/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let url := ctx.paramD "url" ""
  let title := ctx.paramD "title" ""
  let description := ctx.paramD "description" ""
  let source := ctx.paramD "source" ""
  let category := ctx.paramD "category" "General"
  if url.isEmpty || title.isEmpty then return ← badRequest "URL and title are required"
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbNewsItem.TxM.setUrl eid url
    DbNewsItem.TxM.setTitle eid title
    DbNewsItem.TxM.setDescription eid description
    DbNewsItem.TxM.setSource eid source
    DbNewsItem.TxM.setCategory eid category
    audit "UPDATE" "news-item" id [("title", title)]
  let itemId := id
  let _ ← SSE.publishEvent "news" "item-updated" (jsonStr! { itemId, title })
  redirect "/news"

-- Toggle read status
action newsToggleRead "/news/:id/read" POST [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getNewsItem ctx id with
  | none => redirect "/news"
  | some item =>
    let newStatus := !item.isRead
    let eid : EntityId := ⟨id⟩
    runAuditTx! do
      DbNewsItem.TxM.setIsRead eid newStatus
      audit "UPDATE" "news-item" id [("is_read", toString newStatus)]
    let itemId := id
    let _ ← SSE.publishEvent "news" "item-updated" (jsonStr! { itemId, "isRead" : newStatus })
    redirect "/news"

-- Toggle save status
action newsToggleSave "/news/:id/save" POST [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getNewsItem ctx id with
  | none => redirect "/news"
  | some item =>
    let newStatus := !item.isSaved
    let eid : EntityId := ⟨id⟩
    runAuditTx! do
      DbNewsItem.TxM.setIsSaved eid newStatus
      audit "UPDATE" "news-item" id [("is_saved", toString newStatus)]
    let itemId := id
    let _ ← SSE.publishEvent "news" "item-updated" (jsonStr! { itemId, "isSaved" : newStatus })
    redirect "/news"

-- Delete news item
action newsDelete "/news/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbNewsItem.TxM.delete eid
    audit "DELETE" "news-item" id []
  let itemId := id
  let _ ← SSE.publishEvent "news" "item-deleted" (jsonStr! { itemId })
  redirect "/news"

end HomebaseApp.Pages
