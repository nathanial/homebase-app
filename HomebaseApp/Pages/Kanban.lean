/-
  HomebaseApp.Pages.Kanban - Kanban board pages
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
open HomebaseApp.Shared hiding isLoggedIn isAdmin  -- Use Helpers versions
open HomebaseApp.Models
open HomebaseApp.Entities
open HomebaseApp.Helpers
-- Note: Use fully qualified middleware names in page/view/action macros
-- because #generate_pages creates code in a separate elaboration context

/-! ## Data Structures -/

structure Card where
  id : Nat
  title : String
  description : String
  labels : String
  order : Nat
  deriving Inhabited

structure Column where
  id : Nat
  name : String
  order : Nat
  cards : List Card
  deriving Inhabited

/-! ## Database Helpers -/

def getColumns (ctx : Context) : List (EntityId × String × Int) :=
  match ctx.database with
  | none => []
  | some db =>
    let columnIds := db.entitiesWithAttr DbColumn.attr_name
    columnIds.filterMap fun colId =>
      match db.getOne colId DbColumn.attr_name, db.getOne colId DbColumn.attr_order with
      | some (.string name), some (.int order) => some (colId, name, order)
      | _, _ => none

def getCardsForColumn (db : Db) (colId : EntityId) : List Card :=
  let cardIds := db.findByAttrValue DbCard.attr_column (.ref colId)
  let cards := cardIds.filterMap fun cardId =>
    match DbCard.pull db cardId with
    | some dbCard =>
      if dbCard.column != colId then none
      else some { id := dbCard.id, title := dbCard.title, description := dbCard.description,
                  labels := dbCard.labels, order := dbCard.order }
    | none => none
  cards.toArray.qsort (fun a b => a.order < b.order) |>.toList

def getColumnsWithCards (ctx : Context) : List Column :=
  match ctx.database with
  | none => []
  | some db =>
    let rawColumns := getColumns ctx
    let columns := rawColumns.map fun (colId, name, order) =>
      let cards := getCardsForColumn db colId
      { id := colId.id.toNat, name := name, order := order.toNat, cards := cards }
    columns.toArray.qsort (fun a b => a.order < b.order) |>.toList

def getColumn (ctx : Context) (columnId : Nat) : Option Column :=
  (getColumnsWithCards ctx).find? (·.id == columnId)

def getCard (ctx : Context) (cardId : Nat) : Option (Card × Nat) :=
  match ctx.database with
  | none => none
  | some db =>
    let eid : EntityId := ⟨cardId⟩
    match DbCard.pull db eid with
    | some dbCard => some ({ id := dbCard.id, title := dbCard.title, description := dbCard.description,
                             labels := dbCard.labels, order := dbCard.order }, dbCard.column.id.toNat)
    | none => none

def getNextColumnOrder (ctx : Context) : Int :=
  let columns := getColumns ctx
  match columns.map (fun (_, _, order) => order) with
  | [] => 0
  | orders => orders.foldl max 0 + 1

def getNextCardOrder (ctx : Context) (columnId : Nat) : Int :=
  match getColumn ctx columnId with
  | some col =>
    match col.cards.map (·.order) with
    | [] => 0
    | orders => (orders.foldl max 0 : Nat) + 1
  | none => 0

/-! ## View Helpers -/

/-- Attribute to clear modal after form submission -/
def modalClearAttr : Attr :=
  ⟨"hx-on::after-request", "document.getElementById('modal-container').innerHTML = ''"⟩

def labelClass (label : String) : String :=
  match label.trim.toLower with
  | "bug" => "label-bug"
  | "feature" => "label-feature"
  | "urgent" => "label-urgent"
  | "low" => "label-low"
  | "high" => "label-high"
  | "blocked" => "label-blocked"
  | _ => "label-default"

def renderLabel (label : String) : HtmlM Unit := do
  if label.trim.isEmpty then pure ()
  else span [class_ s!"label {labelClass label}"] (text label.trim)

def renderLabels (labelsStr : String) : HtmlM Unit := do
  let labels := labelsStr.splitOn ","
  div [class_ "kanban-labels"] do
    for label in labels do
      renderLabel label

def renderCard (_ctx : Context) (card : Card) : HtmlM Unit := do
  div [id_ s!"card-{card.id}", data_ "card-id" (toString card.id), class_ "kanban-card"] do
    div [class_ "kanban-card-header"] do
      h4 [class_ "kanban-card-title"] (text card.title)
      div [class_ "kanban-card-actions"] do
        -- Edit card button (opens modal)
        button [hx_get s!"/kanban/card/{card.id}/edit",
                hx_target "#modal-container", hx_swap "innerHTML",
                class_ "btn-icon"] (text "e")
        -- Delete card button (SSE refreshes board)
        button [hx_delete s!"/kanban/card/{card.id}",
                hx_swap "none", hx_confirm "Delete this card?",
                class_ "btn-icon btn-icon-danger"] (text "x")
    if !card.labels.isEmpty then renderLabels card.labels
    if !card.description.isEmpty then
      p [class_ "kanban-card-description"] (text card.description)

def renderAddCardButton (columnId : Nat) : HtmlM Unit := do
  button [hx_get s!"/kanban/column/{columnId}/add-card-form",
          hx_target "#modal-container", hx_swap "innerHTML",
          class_ "kanban-add-card"] (text "+ Add card")

def renderColumn (ctx : Context) (col : Column) : HtmlM Unit := do
  div [id_ s!"column-{col.id}", class_ "kanban-column"] do
    div [class_ "kanban-column-header"] do
      h3 [class_ "kanban-column-title"] (text col.name)
      div [class_ "kanban-column-actions"] do
        -- Edit column button (opens modal)
        button [hx_get s!"/kanban/column/{col.id}/edit",
                hx_target "#modal-container", hx_swap "innerHTML",
                class_ "btn-icon"] (text "e")
        -- Delete column button (SSE refreshes board)
        button [hx_delete s!"/kanban/column/{col.id}",
                hx_swap "none", hx_confirm s!"Delete column '{col.name}' and all its cards?",
                class_ "btn-icon btn-icon-danger"] (text "x")
    div [id_ s!"column-cards-{col.id}", data_ "column-id" (toString col.id),
         class_ "kanban-column-cards sortable-cards"] do
      for card in col.cards do renderCard ctx card
    renderAddCardButton col.id

def renderAddColumnButton : HtmlM Unit := do
  div [class_ "kanban-add-column-wrapper"] do
    button [hx_get "/kanban/add-column-form",
            hx_target "#modal-container", hx_swap "innerHTML",
            class_ "kanban-add-column"] (text "+ Add column")

def boardContent (ctx : Context) (columns : List Column) : HtmlM Unit := do
  div [id_ "kanban-board", class_ "kanban-board"] do
    div [class_ "kanban-header"] do
      h1 [class_ "kanban-title"] (text "Kanban Board")
      div [class_ "kanban-meta"] do
        span [id_ "sse-status", class_ "status-indicator"] (text "* Live")
        span [class_ "kanban-count"] (text s!"{columns.length} columns")
    div [class_ "kanban-scroll"] do
      div [id_ "board-columns", class_ "kanban-columns"] do
        for col in columns do renderColumn ctx col
        renderAddColumnButton
  div [id_ "modal-container"] (pure ())
  script [src_ "/js/kanban.js"]

/-! ## Pages -/

-- Main kanban board
view kanban "/kanban" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let columns := getColumnsWithCards ctx
  html (Shared.render ctx "Kanban - Homebase" "/kanban" (boardContent ctx columns))

-- Get all columns (for SSE refresh)
view kanbanColumns "/kanban/columns" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let columns := getColumnsWithCards ctx
  html (HtmlM.render do
    for col in columns do renderColumn ctx col
    renderAddColumnButton)

-- Note: SSE endpoint "/events/kanban" is registered separately in Main.lean

-- Add column form
view kanbanAddColumnForm "/kanban/add-column-form" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  html (HtmlM.render do
    div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
      div [class_ "modal-container modal-sm"] do
        h3 [class_ "modal-title"] (text "Add Column")
        form [hx_post "/kanban/column", hx_swap "none", modalClearAttr] do
          csrfField ctx.csrfToken
          div [class_ "form-stack"] do
            div [class_ "form-group"] do
              label [for_ "name", class_ "form-label"] (text "Column Name")
              input [type_ "text", name_ "name", id_ "name", class_ "form-input",
                     placeholder_ "Column name", required_, autofocus_]
            div [class_ "form-actions"] do
              button [type_ "button", class_ "btn btn-secondary",
                      attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
              button [type_ "submit", class_ "btn btn-primary"] (text "Add Column"))

-- Create column
action kanbanCreateColumn "/kanban/column" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let name := ctx.paramD "name" ""
  if name.isEmpty then return ← badRequest "Column name is required"
  let ctx ← getCtx
  let order := getNextColumnOrder ctx
  let (eid, _) ← withNewEntityAudit! fun eid => do
    let dbCol : DbColumn := { id := eid.id.toNat, name := name, order := order.toNat }
    DbColumn.TxM.create eid dbCol
    audit "CREATE" "column" eid.id.toNat [("name", name)]
  let _ ← SSE.publishEvent "kanban" "column-created" (jsonStr! { "columnId" : eid.id.toNat, name })
  html ""

-- Get column
view kanbanGetColumn "/kanban/column/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getColumn ctx id with
  | none => notFound "Column not found"
  | some col => html (HtmlM.render (renderColumn ctx col))

-- Edit column form
view kanbanEditColumnForm "/kanban/column/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getColumn ctx id with
  | none => notFound "Column not found"
  | some col =>
    html (HtmlM.render do
      div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
        div [class_ "modal-container modal-sm"] do
          h3 [class_ "modal-title"] (text "Edit Column")
          form [hx_put s!"/kanban/column/{col.id}", hx_swap "none", modalClearAttr] do
            csrfField ctx.csrfToken
            div [class_ "form-stack"] do
              div [class_ "form-group"] do
                label [for_ "name", class_ "form-label"] (text "Column Name")
                input [type_ "text", name_ "name", id_ "name", value_ col.name,
                       class_ "form-input", placeholder_ "Column name", required_, autofocus_]
              div [class_ "form-actions"] do
                button [type_ "button", class_ "btn btn-secondary",
                        attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
                button [type_ "submit", class_ "btn btn-primary"] (text "Save"))

-- Update column
action kanbanUpdateColumn "/kanban/column/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let name := ctx.paramD "name" ""
  if name.isEmpty then return ← badRequest "Column name is required"
  let oldName := match getColumn ctx id with
    | some col => col.name
    | none => "(unknown)"
  runAuditTx! do
    DbColumn.TxM.setName ⟨id⟩ name
    audit "UPDATE" "column" id [("old_name", oldName), ("new_name", name)]
  let _ ← SSE.publishEvent "kanban" "column-updated" (jsonStr! { "columnId" : id, name })
  html ""

-- Delete column
action kanbanDeleteColumn "/kanban/column/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let some db := ctx.database | return ← badRequest "Database not available"
  let columnName := match getColumn ctx id with
    | some col => col.name
    | none => "(unknown)"
  let colId : EntityId := ⟨id⟩
  let cardIds := db.findByAttrValue DbCard.attr_column (.ref colId)
  let cardCount := cardIds.length
  runAuditTx! do
    for cardId in cardIds do
      DbCard.TxM.delete cardId
    DbColumn.TxM.delete colId
    audit "DELETE" "column" id [("name", columnName), ("cascade_cards", toString cardCount)]
  let _ ← SSE.publishEvent "kanban" "column-deleted" (jsonStr! { "columnId" : id })
  html ""

-- Add card form
view kanbanAddCardForm "/kanban/column/:columnId/add-card-form" [HomebaseApp.Middleware.authRequired] (columnId : Nat) do
  let ctx ← getCtx
  html (HtmlM.render do
    div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
      div [class_ "modal-container modal-md"] do
        h3 [class_ "modal-title"] (text "Add Card")
        form [hx_post "/kanban/card", hx_swap "none", modalClearAttr] do
          csrfField ctx.csrfToken
          input [type_ "hidden", name_ "column_id", value_ (toString columnId)]
          div [class_ "form-stack"] do
            div [class_ "form-group"] do
              label [for_ "title", class_ "form-label"] (text "Title")
              input [type_ "text", name_ "title", id_ "title", class_ "form-input",
                     placeholder_ "Card title", required_, autofocus_]
            div [class_ "form-group"] do
              label [for_ "description", class_ "form-label"] (text "Description")
              textarea [name_ "description", id_ "description", rows_ 2, class_ "form-textarea",
                        placeholder_ "Description (optional)"]
            div [class_ "form-group"] do
              label [for_ "labels", class_ "form-label"] (text "Labels")
              input [type_ "text", name_ "labels", id_ "labels", class_ "form-input",
                     placeholder_ "bug, feature, urgent (comma-separated)"]
            div [class_ "form-actions"] do
              button [type_ "button", class_ "btn btn-secondary",
                      attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
              button [type_ "submit", class_ "btn btn-primary"] (text "Add Card"))

-- Add card button
view kanbanAddCardButton "/kanban/column/:columnId/add-card-button" [HomebaseApp.Middleware.authRequired] (columnId : Nat) do
  html (HtmlM.render (renderAddCardButton columnId))

-- Create card
action kanbanCreateCard "/kanban/card" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  let description := ctx.paramD "description" ""
  let labels := ctx.paramD "labels" ""
  let columnIdStr := ctx.paramD "column_id" ""
  if title.isEmpty then return ← badRequest "Card title is required"
  let some columnId := columnIdStr.toNat? | return ← badRequest "Invalid column ID"
  let ctx ← getCtx
  let order := getNextCardOrder ctx columnId
  let (eid, _) ← withNewEntityAudit! fun eid => do
    let dbCard : DbCard := {
      id := eid.id.toNat, title := title, description := description,
      labels := labels, order := order.toNat, column := ⟨columnId⟩
    }
    DbCard.TxM.create eid dbCard
    audit "CREATE" "card" eid.id.toNat [("title", title), ("column_id", toString columnId)]
  let _ ← SSE.publishEvent "kanban" "card-created" (jsonStr! { "cardId" : eid.id.toNat, columnId, title })
  html ""

-- Get card
view kanbanGetCard "/kanban/card/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getCard ctx id with
  | none => notFound "Card not found"
  | some (card, _) => html (HtmlM.render (renderCard ctx card))

-- Edit card form
view kanbanEditCardForm "/kanban/card/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getCard ctx id with
  | none => notFound "Card not found"
  | some (card, _) =>
    html (HtmlM.render do
      div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
        div [class_ "modal-container modal-md"] do
          h3 [class_ "modal-title"] (text "Edit Card")
          form [hx_put s!"/kanban/card/{card.id}", hx_swap "none", modalClearAttr] do
            csrfField ctx.csrfToken
            div [class_ "form-stack"] do
              div [class_ "form-group"] do
                label [for_ "title", class_ "form-label"] (text "Title")
                input [type_ "text", name_ "title", id_ "title", value_ card.title,
                       class_ "form-input", placeholder_ "Card title", required_, autofocus_]
              div [class_ "form-group"] do
                label [for_ "description", class_ "form-label"] (text "Description")
                textarea [name_ "description", id_ "description", rows_ 3, class_ "form-textarea",
                          placeholder_ "Description (optional)"] card.description
              div [class_ "form-group"] do
                label [for_ "labels", class_ "form-label"] (text "Labels")
                input [type_ "text", name_ "labels", id_ "labels", value_ card.labels,
                       class_ "form-input", placeholder_ "bug, feature, urgent (comma-separated)"]
              div [class_ "form-actions"] do
                button [type_ "button", class_ "btn btn-secondary",
                        attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
                button [type_ "submit", class_ "btn btn-primary"] (text "Save Changes"))

-- Update card
action kanbanUpdateCard "/kanban/card/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  let description := ctx.paramD "description" ""
  let labels := ctx.paramD "labels" ""
  if title.isEmpty then return ← badRequest "Card title is required"
  let (oldTitle, oldDesc, oldLabels) := match getCard ctx id with
    | some (card, _) => (card.title, card.description, card.labels)
    | none => ("", "", "")
  -- Build changes list before transaction
  let mut changes : List (String × String) := []
  if oldTitle != title then changes := changes ++ [("old_title", oldTitle), ("new_title", title)]
  if oldDesc != description then changes := changes ++ [("description_changed", "true")]
  if oldLabels != labels then changes := changes ++ [("old_labels", oldLabels), ("new_labels", labels)]
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbCard.TxM.setTitle eid title
    DbCard.TxM.setDescription eid description
    DbCard.TxM.setLabels eid labels
    audit "UPDATE" "card" id changes
  let _ ← SSE.publishEvent "kanban" "card-updated" (jsonStr! { "cardId" : id, title })
  html ""

-- Delete card
action kanbanDeleteCard "/kanban/card/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let (cardTitle, columnId) := match getCard ctx id with
    | some (card, colId) => (card.title, colId)
    | none => ("(unknown)", 0)
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbCard.TxM.delete eid
    audit "DELETE" "card" id [("title", cardTitle), ("column_id", toString columnId)]
  let _ ← SSE.publishEvent "kanban" "card-deleted" (jsonStr! { "cardId" : id })
  html ""

-- Move card
action kanbanMoveCard "/kanban/card/:id/move" POST [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let columnIdStr := ctx.paramD "column_id" ""
  let some newColumnId := columnIdStr.toNat? | return ← badRequest "Invalid column ID"
  let oldColumnId := match getCard ctx id with
    | some (_, colId) => colId
    | none => 0
  let cardEid : EntityId := ⟨id⟩
  let ctx ← getCtx
  let order := getNextCardOrder ctx newColumnId
  runAuditTx! do
    DbCard.TxM.setColumn cardEid ⟨newColumnId⟩
    DbCard.TxM.setOrder cardEid order.toNat
    audit "MOVE" "card" id [("old_column_id", toString oldColumnId), ("new_column_id", toString newColumnId)]
  let ctx ← getCtx
  match getCard ctx id with
  | none => notFound "Card not found"
  | some (card, _) =>
    let _ ← SSE.publishEvent "kanban" "card-moved" (jsonStr! { "cardId" : id, newColumnId })
    html (HtmlM.render (renderCard ctx card))

-- Reorder card (drag and drop)
action kanbanReorderCard "/kanban/card/:id/reorder" POST [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let columnIdStr := ctx.paramD "column_id" ""
  let positionStr := ctx.paramD "position" "0"
  let some newColumnId := columnIdStr.toNat? | return ← badRequest "Invalid column ID"
  let some position := positionStr.toNat? | return ← badRequest "Invalid position"
  let some db := ctx.database | return ← badRequest "Database not available"
  let (oldColumnId, oldOrder) := match getCard ctx id with
    | some (card, colId) => (colId, card.order)
    | none => (0, 0)
  let cardEid : EntityId := ⟨id⟩
  let colEid : EntityId := ⟨newColumnId⟩
  let targetCards := getCardsForColumn db colEid
  let otherCards := targetCards.filter (·.id != id)
  runAuditTx! do
    DbCard.TxM.setColumn cardEid colEid
    let mut currentOrder := 0
    let mut insertedCard := false
    let mut idx := 0
    for card in otherCards do
      if idx == position && !insertedCard then
        DbCard.TxM.setOrder cardEid currentOrder
        currentOrder := currentOrder + 1
        insertedCard := true
      if card.order != currentOrder then
        DbCard.TxM.setOrder ⟨card.id⟩ currentOrder
      currentOrder := currentOrder + 1
      idx := idx + 1
    if !insertedCard then
      DbCard.TxM.setOrder cardEid currentOrder
    audit "REORDER" "card" id [
      ("old_column_id", toString oldColumnId), ("new_column_id", toString newColumnId),
      ("old_position", toString oldOrder), ("new_position", toString position)
    ]
  let _ ← SSE.publishEvent "kanban" "card-reordered" (jsonStr! { "cardId" : id, "columnId" : newColumnId, position })
  html ""

end HomebaseApp.Pages
