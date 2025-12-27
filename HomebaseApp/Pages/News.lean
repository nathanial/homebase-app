/-
  HomebaseApp.Pages.News - Link aggregator with read/save tracking
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

/-! ## Helpers -/

/-- Get current time in milliseconds -/
def newsGetNowMs : IO Nat := do
  let output ← IO.Process.output { cmd := "date", args := #["+%s"] }
  let seconds := output.stdout.trim.toNat?.getD 0
  return seconds * 1000

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

/-- Get current user's EntityId -/
def newsGetCurrentUserEid (ctx : Context) : Option EntityId :=
  match currentUserId ctx with
  | some idStr => idStr.toNat?.map fun n => ⟨n⟩
  | none => none

/-- Extract domain from URL -/
def newsExtractDomain (url : String) : String :=
  -- Simple extraction: look for :// and take text until next /
  let parts := url.splitOn "://"
  match parts with
  | [_, rest] =>
    let domainParts := rest.splitOn "/"
    match domainParts.head? with
    | some domain => domain.splitOn "www." |>.getLast!
    | none => ""
  | _ => ""

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

/-! ## View Helpers -/

/-- Attribute to clear modal after form submission -/
def newsModalClearAttr : Attr :=
  ⟨"hx-on::after-request", "document.getElementById('modal-container').innerHTML = ''"⟩

/-- Get active class for filter tab -/
def newsFilterClass (currentFilter target : String) : String :=
  if currentFilter == target then "news-filter-tab active" else "news-filter-tab"

/-- Render filter tabs -/
def newsRenderFilterTabs (currentFilter : String) (unreadCount savedCount : Nat) : HtmlM Unit := do
  div [class_ "news-filters"] do
    a [href_ "/news", class_ (newsFilterClass currentFilter "all")] (text "All")
    a [href_ "/news?filter=unread", class_ (newsFilterClass currentFilter "unread")] do
      text "Unread"
      if unreadCount > 0 then
        span [class_ "news-filter-badge"] (text (toString unreadCount))
    a [href_ "/news?filter=saved", class_ (newsFilterClass currentFilter "saved")] do
      text "Saved"
      if savedCount > 0 then
        span [class_ "news-filter-badge"] (text (toString savedCount))
    -- Category filters
    for cat in newsCategories do
      a [href_ s!"/news?filter={cat}", class_ (newsFilterClass currentFilter cat)] (text cat)

/-- Render a single news item row -/
def newsRenderItemRow (item : NewsItemView) (now : Nat) : HtmlM Unit := do
  let readClass := if item.isRead then " read" else ""
  div [id_ s!"item-{item.id}", class_ s!"news-item-row{readClass}"] do
    -- Main content
    div [class_ "news-item-main"] do
      div [class_ "news-item-header"] do
        if item.isSaved then
          span [class_ "news-item-saved-indicator", title_ "Saved"] (text "")
        a [href_ item.url, target_ "_blank", class_ "news-item-title",
           hx_post s!"/news/{item.id}/read", hx_swap "none"] (text item.title)
      if !item.description.isEmpty then
        p [class_ "news-item-description"] (text (item.description.take 200))
      div [class_ "news-item-meta"] do
        span [class_ "news-item-source"] (text (if item.source.isEmpty then newsExtractDomain item.url else item.source))
        span [class_ "news-item-category"] (text item.category)
        span [class_ "news-item-time"] (text (newsFormatRelativeTime item.addedAt now))
    -- Actions
    div [class_ "news-item-actions"] do
      button [hx_post s!"/news/{item.id}/read", hx_swap "none",
              class_ (if item.isRead then "btn-icon" else "btn-icon btn-icon-active"),
              title_ (if item.isRead then "Mark unread" else "Mark read")] do
        text (if item.isRead then "o" else ".")
      button [hx_post s!"/news/{item.id}/save", hx_swap "none",
              class_ (if item.isSaved then "btn-icon btn-icon-active" else "btn-icon"),
              title_ (if item.isSaved then "Unsave" else "Save")] (text "*")
      button [hx_get s!"/news/{item.id}/edit", hx_target "#modal-container",
              hx_swap "innerHTML", class_ "btn-icon", title_ "Edit"] (text "e")
      button [hx_delete s!"/news/{item.id}", hx_swap "none",
              hx_confirm "Delete this item?",
              class_ "btn-icon btn-icon-danger", title_ "Delete"] (text "x")

/-- Render news items list -/
def newsRenderItemsList (items : List NewsItemView) (now : Nat) : HtmlM Unit := do
  if items.isEmpty then
    div [class_ "news-empty"] do
      div [class_ "news-empty-icon"] (text "📰")
      p [] (text "No news items")
      p [class_ "text-muted"] (text "Add some links to get started!")
  else
    div [class_ "news-items-list"] do
      for item in items do newsRenderItemRow item now

/-- Main news page content -/
def newsPageContent (ctx : Context) (items : List NewsItemView) (filter : String)
    (allItems : List NewsItemView) (now : Nat) : HtmlM Unit := do
  let unreadCount := allItems.filter (!·.isRead) |>.length
  let savedCount := allItems.filter (·.isSaved) |>.length
  div [class_ "news-container"] do
    -- Header
    div [class_ "news-header"] do
      h1 [] (text "News")
      button [hx_get "/news/add", hx_target "#modal-container",
              hx_swap "innerHTML", class_ "btn btn-primary"] (text "+ Add Link")
    -- Filters
    newsRenderFilterTabs filter unreadCount savedCount
    -- Items
    div [id_ "news-items"] do
      newsRenderItemsList items now
    -- Modal container
    div [id_ "modal-container"] (pure ())
    -- SSE script
    script [src_ "/js/news.js"]

/-! ## Pages -/

-- Main news page
view newsPage "/news" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let filter := ctx.paramD "filter" "all"
  let now ← newsGetNowMs
  let allItems := getNewsItems ctx
  let items := getNewsItemsFiltered ctx filter
  html (Shared.render ctx "News - Homebase" "/news"
    (newsPageContent ctx items filter allItems now))

-- Add link form (modal)
view newsAddForm "/news/add" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  html (HtmlM.render do
    div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
      div [class_ "modal-container modal-md"] do
        h3 [class_ "modal-title"] (text "Add Link")
        form [hx_post "/news/create", hx_swap "none", newsModalClearAttr] do
          csrfField ctx.csrfToken
          div [class_ "form-stack"] do
            div [class_ "form-group"] do
              label [for_ "url", class_ "form-label"] (text "URL")
              input [type_ "url", name_ "url", id_ "url", class_ "form-input",
                     placeholder_ "https://...", required_, autofocus_]
            div [class_ "form-group"] do
              label [for_ "title", class_ "form-label"] (text "Title")
              input [type_ "text", name_ "title", id_ "title", class_ "form-input",
                     placeholder_ "Article title", required_]
            div [class_ "form-group"] do
              label [for_ "description", class_ "form-label"] (text "Description (optional)")
              textarea [name_ "description", id_ "description", class_ "form-textarea", rows_ 2,
                        placeholder_ "Brief summary..."] ""
            div [class_ "form-row"] do
              div [class_ "form-group"] do
                label [for_ "source", class_ "form-label"] (text "Source (optional)")
                input [type_ "text", name_ "source", id_ "source", class_ "form-input",
                       placeholder_ "e.g., TechCrunch"]
              div [class_ "form-group"] do
                label [for_ "category", class_ "form-label"] (text "Category")
                select [name_ "category", id_ "category", class_ "form-select"] do
                  for cat in newsCategories do
                    option [value_ cat] cat
            div [class_ "form-actions"] do
              button [type_ "button", class_ "btn btn-secondary",
                      attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
              button [type_ "submit", class_ "btn btn-primary"] (text "Add"))

-- Edit item form (modal)
view newsEditForm "/news/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getNewsItem ctx id with
  | none => notFound "Item not found"
  | some item =>
    html (HtmlM.render do
      div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
        div [class_ "modal-container modal-md"] do
          h3 [class_ "modal-title"] (text "Edit Link")
          form [hx_put s!"/news/{id}", hx_swap "none", newsModalClearAttr] do
            csrfField ctx.csrfToken
            div [class_ "form-stack"] do
              div [class_ "form-group"] do
                label [for_ "url", class_ "form-label"] (text "URL")
                input [type_ "url", name_ "url", id_ "url", class_ "form-input",
                       value_ item.url, required_]
              div [class_ "form-group"] do
                label [for_ "title", class_ "form-label"] (text "Title")
                input [type_ "text", name_ "title", id_ "title", class_ "form-input",
                       value_ item.title, required_]
              div [class_ "form-group"] do
                label [for_ "description", class_ "form-label"] (text "Description")
                textarea [name_ "description", id_ "description", class_ "form-textarea", rows_ 2] item.description
              div [class_ "form-row"] do
                div [class_ "form-group"] do
                  label [for_ "source", class_ "form-label"] (text "Source")
                  input [type_ "text", name_ "source", id_ "source", class_ "form-input",
                         value_ item.source]
                div [class_ "form-group"] do
                  label [for_ "category", class_ "form-label"] (text "Category")
                  select [name_ "category", id_ "category", class_ "form-select"] do
                    for cat in newsCategories do
                      if cat == item.category then
                        option [value_ cat, selected_] cat
                      else
                        option [value_ cat] cat
              div [class_ "form-actions"] do
                button [type_ "button", class_ "btn btn-secondary",
                        attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
                button [type_ "submit", class_ "btn btn-primary"] (text "Save"))

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
