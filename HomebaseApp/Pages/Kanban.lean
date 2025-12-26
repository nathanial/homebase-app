/-
  HomebaseApp.Pages.Kanban - Kanban board pages (unified route + logic + view)
-/
import Scribe
import Loom
import Ledger
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Helpers

namespace HomebaseApp.Pages

open Scribe
open Loom hiding Action
open Loom.Page
open Loom.ActionM
open Loom.Json
open Loom.Action (InteractionFactory Interaction HxConfig Swap Target)
open Ledger
open HomebaseApp.Shared hiding isLoggedIn isAdmin  -- Use Helpers versions
open HomebaseApp.Models
open HomebaseApp.Entities
open HomebaseApp.Helpers

/-! ## Trigger-Only Interactions -/

/-- Delete column interaction base (for button generation) -/
def deleteColumnBase : InteractionFactory Nat :=
  InteractionFactory.delete "deleteColumn" "/kanban/column/:id"
    (pathFor := fun id => s!"/kanban/column/{id}")
    |>.swap .outerHTML

/-- Delete a column attrs - includes dynamic confirm with column name -/
def deleteColumnAttrs (colId : Nat) (colName : String) : List Attr :=
  deleteColumnBase.attrsFor colId ++ [
    ⟨"hx-target", s!"#column-{colId}"⟩,
    ⟨"hx-confirm", s!"Delete column '{colName}' and all its cards?"⟩
  ]

interaction createColumn "/kanban/column" post
  |>.target (.css "#board-columns")
  |>.swap .beforeend

interaction updateColumn "/kanban/column/:id" put (id : Nat)
  |>.swap .outerHTML

interaction createCard "/kanban/card" post

interaction updateCard "/kanban/card/:id" put (id : Nat)
  |>.swap .outerHTML

/-- Attribute to clear modal after form submission -/
def modalClearAttr : Attr :=
  ⟨"hx-on::after-request", "document.getElementById('modal-container').innerHTML = ''"⟩

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

/-! ## Interactions with Handlers -/

-- Delete card (unified interaction with handler)
interaction deleteCard "/kanban/card/:id" delete (id : Nat)
  |>.swap .outerHTML
  |>.confirm "Delete this card?"
handler do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  match ctx.database with
  | none => badRequest "Database not available"
  | some db =>
    let (cardTitle, columnId) := match getCard ctx id with
      | some (card, colId) => (card.title, colId)
      | none => ("(unknown)", 0)
    let eid : EntityId := ⟨id⟩
    let txOps := DbCard.retractionOps db eid
    match ← transact txOps with
    | .ok () =>
      let ctx ← getCtx
      logAudit ctx "DELETE" "card" id [("title", cardTitle), ("column_id", toString columnId)]
      let _ ← SSE.publishEvent "kanban" "card-deleted" (jsonStr! { "cardId" : id })
      html ""
    | .error e =>
      logAuditError ctx "DELETE" "card" [("card_id", toString id), ("error", toString e)]
      badRequest s!"Failed to delete card: {e}"

-- Delete column (unified interaction with handler)
-- Note: Uses deleteColumnAttrs in view for dynamic confirm message
interaction deleteColumn "/kanban/column/:id" delete (id : Nat)
  |>.swap .outerHTML
handler do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  match ctx.database with
  | none => badRequest "Database not available"
  | some db =>
    let columnName := match getColumn ctx id with
      | some col => col.name
      | none => "(unknown)"
    let colId : EntityId := ⟨id⟩
    let cardIds := db.findByAttrValue DbCard.attr_column (.ref colId)
    let cardCount := cardIds.length
    let mut txOps : List TxOp := []
    for cardId in cardIds do
      txOps := txOps ++ DbCard.retractionOps db cardId
    txOps := txOps ++ DbColumn.retractionOps db colId
    match ← transact txOps with
    | .ok () =>
      let ctx ← getCtx
      logAudit ctx "DELETE" "column" id [("name", columnName), ("cascade_cards", toString cardCount)]
      let _ ← SSE.publishEvent "kanban" "column-deleted" (jsonStr! { "columnId" : id })
      html ""
    | .error e =>
      logAuditError ctx "DELETE" "column" [("column_id", toString id), ("error", toString e)]
      badRequest s!"Failed to delete column: {e}"

-- Add column form (unified)
interaction addColumnForm "/kanban/add-column-form" get
  |>.target (.css "#modal-container")
  |>.swap .innerHTML
handler do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  html (HtmlM.render do
    div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
      div [class_ "modal-container modal-sm"] do
        h3 [class_ "modal-title"] (text "Add Column")
        form (createColumn.attrs ++ [modalClearAttr]) do
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

-- Edit column form (unified)
interaction editColumnForm "/kanban/column/:id/edit" get (id : Nat)
  |>.target (.css "#modal-container")
  |>.swap .innerHTML
handler do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  match getColumn ctx id with
  | none => notFound "Column not found"
  | some col =>
    html (HtmlM.render do
      div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
        div [class_ "modal-container modal-sm"] do
          h3 [class_ "modal-title"] (text "Edit Column")
          form (updateColumn.attrsFor col.id ++ [modalClearAttr]) do
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

-- Add card form (unified)
interaction addCardForm "/kanban/column/:columnId/add-card-form" get (columnId : Nat)
  |>.target (.css "#modal-container")
  |>.swap .innerHTML
handler do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  html (HtmlM.render do
    div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
      div [class_ "modal-container modal-md"] do
        h3 [class_ "modal-title"] (text "Add Card")
        form (createCard.attrs ++ [hx_target s!"#column-cards-{columnId}", hx_swap "beforeend", modalClearAttr]) do
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

-- Edit card form (unified)
interaction editCardForm "/kanban/card/:id/edit" get (id : Nat)
  |>.target (.css "#modal-container")
  |>.swap .innerHTML
handler do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  match getCard ctx id with
  | none => notFound "Card not found"
  | some (card, _) =>
    html (HtmlM.render do
      div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
        div [class_ "modal-container modal-md"] do
          h3 [class_ "modal-title"] (text "Edit Card")
          form (updateCard.attrsFor card.id ++ [hx_target s!"#card-{card.id}", modalClearAttr]) do
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

/-! ## View Helpers -/

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

def renderCard (ctx : Context) (card : Card) : HtmlM Unit := do
  div [id_ s!"card-{card.id}", data_ "card-id" (toString card.id), class_ "kanban-card"] do
    div [class_ "kanban-card-header"] do
      h4 [class_ "kanban-card-title"] (text card.title)
      div [class_ "kanban-card-actions"] do
        editCardForm.button card.id "e" [class_ "btn-icon"]
        deleteCard.button card.id "x" [class_ "btn-icon btn-icon-danger"]
    if !card.labels.isEmpty then renderLabels card.labels
    if !card.description.isEmpty then
      p [class_ "kanban-card-description"] (text card.description)

def renderAddCardButton (columnId : Nat) : HtmlM Unit := do
  addCardForm.button columnId "+ Add card" [class_ "kanban-add-card"]

def renderColumn (ctx : Context) (col : Column) : HtmlM Unit := do
  div [id_ s!"column-{col.id}", class_ "kanban-column"] do
    div [class_ "kanban-column-header"] do
      h3 [class_ "kanban-column-title"] (text col.name)
      div [class_ "kanban-column-actions"] do
        editColumnForm.button col.id "e" [class_ "btn-icon"]
        button (deleteColumnAttrs col.id col.name ++ [class_ "btn-icon btn-icon-danger"]) (text "x")
    div [id_ s!"column-cards-{col.id}", data_ "column-id" (toString col.id),
         class_ "kanban-column-cards sortable-cards"] do
      for card in col.cards do renderCard ctx card
    renderAddCardButton col.id

def renderAddColumnButton : HtmlM Unit := do
  div [class_ "kanban-add-column-wrapper"] do
    addColumnForm.button "+ Add column" [class_ "kanban-add-column"]

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
page kanban "/kanban" GET do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  let columns := getColumnsWithCards ctx
  html (Shared.render ctx "Kanban - Homebase" "/kanban" (boardContent ctx columns))

-- Get all columns (for SSE refresh)
page kanbanColumns "/kanban/columns" GET do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  let columns := getColumnsWithCards ctx
  html (HtmlM.render do
    for col in columns do renderColumn ctx col
    renderAddColumnButton)

-- Note: SSE endpoint "/events/kanban" is registered separately in Main.lean

-- Create column
page kanbanCreateColumn "/kanban/column" POST do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  let name := ctx.paramD "name" ""
  if name.isEmpty then return ← badRequest "Column name is required"
  match ← allocEntityId with
  | none => badRequest "Database not available"
  | some eid =>
    let ctx ← getCtx
    let order := getNextColumnOrder ctx
    let dbCol : DbColumn := { id := eid.id.toNat, name := name, order := order.toNat }
    let tx := DbColumn.createOps eid dbCol
    match ← transact tx with
    | .ok () =>
      let ctx ← getCtx
      logAudit ctx "CREATE" "column" eid.id.toNat [("name", name)]
      let col : Column := { id := eid.id.toNat, name := name, order := order.toNat, cards := [] }
      let colHtml := HtmlM.render (renderColumn ctx col)
      let btnHtml := HtmlM.render renderAddColumnButton
      let _ ← SSE.publishEvent "kanban" "column-created" (jsonStr! { "columnId" : eid.id.toNat, name })
      html (colHtml ++ btnHtml)
    | .error e =>
      logAuditError ctx "CREATE" "column" [("name", name), ("error", toString e)]
      badRequest s!"Failed to create column: {e}"

-- Get column
page kanbanGetColumn "/kanban/column/:id" GET (id : Nat) do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  match getColumn ctx id with
  | none => notFound "Column not found"
  | some col => html (HtmlM.render (renderColumn ctx col))

-- Update column
page kanbanUpdateColumn "/kanban/column/:id" PUT (id : Nat) do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  let name := ctx.paramD "name" ""
  if name.isEmpty then return ← badRequest "Column name is required"
  match ctx.database with
  | none => badRequest "Database not available"
  | some db =>
    let oldName := match getColumn ctx id with
      | some col => col.name
      | none => "(unknown)"
    let tx := DbColumn.set_name db ⟨id⟩ name
    match ← transact tx with
    | .ok () =>
      let ctx ← getCtx
      match getColumn ctx id with
      | none => notFound "Column not found"
      | some col =>
        logAudit ctx "UPDATE" "column" id [("old_name", oldName), ("new_name", name)]
        let _ ← SSE.publishEvent "kanban" "column-updated" (jsonStr! { "columnId" : id, name })
        html (HtmlM.render (renderColumn ctx col))
    | .error e =>
      logAuditError ctx "UPDATE" "column" [("column_id", toString id), ("error", toString e)]
      badRequest s!"Failed to update column: {e}"

-- Add card button
page kanbanAddCardButton "/kanban/column/:columnId/add-card-button" GET (columnId : Nat) do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  html (HtmlM.render (renderAddCardButton columnId))

-- Create card
page kanbanCreateCard "/kanban/card" POST do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  let title := ctx.paramD "title" ""
  let description := ctx.paramD "description" ""
  let labels := ctx.paramD "labels" ""
  let columnIdStr := ctx.paramD "column_id" ""
  if title.isEmpty then return ← badRequest "Card title is required"
  match columnIdStr.toNat? with
  | none => badRequest "Invalid column ID"
  | some columnId =>
    match ← allocEntityId with
    | none => badRequest "Database not available"
    | some eid =>
      let ctx ← getCtx
      let order := getNextCardOrder ctx columnId
      let dbCard : DbCard := {
        id := eid.id.toNat, title := title, description := description,
        labels := labels, order := order.toNat, column := ⟨columnId⟩
      }
      let tx := DbCard.createOps eid dbCard
      match ← transact tx with
      | .ok () =>
        let ctx ← getCtx
        logAudit ctx "CREATE" "card" eid.id.toNat [("title", title), ("column_id", toString columnId)]
        let card : Card := { id := eid.id.toNat, title := title, description := description,
                             labels := labels, order := order.toNat }
        let _ ← SSE.publishEvent "kanban" "card-created" (jsonStr! { "cardId" : eid.id.toNat, columnId, title })
        html (HtmlM.render (renderCard ctx card))
      | .error e =>
        logAuditError ctx "CREATE" "card" [("title", title), ("error", toString e)]
        badRequest s!"Failed to create card: {e}"

-- Get card
page kanbanGetCard "/kanban/card/:id" GET (id : Nat) do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  match getCard ctx id with
  | none => notFound "Card not found"
  | some (card, _) => html (HtmlM.render (renderCard ctx card))

-- Update card
page kanbanUpdateCard "/kanban/card/:id" PUT (id : Nat) do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  let title := ctx.paramD "title" ""
  let description := ctx.paramD "description" ""
  let labels := ctx.paramD "labels" ""
  if title.isEmpty then return ← badRequest "Card title is required"
  match ctx.database with
  | none => badRequest "Database not available"
  | some db =>
    let (oldTitle, oldDesc, oldLabels) := match getCard ctx id with
      | some (card, _) => (card.title, card.description, card.labels)
      | none => ("", "", "")
    let eid : EntityId := ⟨id⟩
    let tx := DbCard.set_title db eid title ++
              DbCard.set_description db eid description ++
              DbCard.set_labels db eid labels
    match ← transact tx with
    | .ok () =>
      let ctx ← getCtx
      match getCard ctx id with
      | none => notFound "Card not found"
      | some (card, _) =>
        let mut changes : List (String × String) := []
        if oldTitle != title then changes := changes ++ [("old_title", oldTitle), ("new_title", title)]
        if oldDesc != description then changes := changes ++ [("description_changed", "true")]
        if oldLabels != labels then changes := changes ++ [("old_labels", oldLabels), ("new_labels", labels)]
        logAudit ctx "UPDATE" "card" id changes
        let _ ← SSE.publishEvent "kanban" "card-updated" (jsonStr! { "cardId" : id, title })
        html (HtmlM.render (renderCard ctx card))
    | .error e =>
      logAuditError ctx "UPDATE" "card" [("card_id", toString id), ("error", toString e)]
      badRequest s!"Failed to update card: {e}"

-- Move card
page kanbanMoveCard "/kanban/card/:id/move" POST (id : Nat) do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  let columnIdStr := ctx.paramD "column_id" ""
  match columnIdStr.toNat? with
  | none => badRequest "Invalid column ID"
  | some newColumnId =>
    match ctx.database with
    | none => badRequest "Database not available"
    | some db =>
      let oldColumnId := match getCard ctx id with
        | some (_, colId) => colId
        | none => 0
      let cardEid : EntityId := ⟨id⟩
      let order := getNextCardOrder ctx newColumnId
      let tx := DbCard.set_column db cardEid ⟨newColumnId⟩ ++
                DbCard.set_order db cardEid order.toNat
      match ← transact tx with
      | .ok () =>
        let ctx ← getCtx
        match getCard ctx id with
        | none => notFound "Card not found"
        | some (card, _) =>
          logAudit ctx "MOVE" "card" id [("old_column_id", toString oldColumnId), ("new_column_id", toString newColumnId)]
          let _ ← SSE.publishEvent "kanban" "card-moved" (jsonStr! { "cardId" : id, newColumnId })
          html (HtmlM.render (renderCard ctx card))
      | .error e =>
        logAuditError ctx "MOVE" "card" [("card_id", toString id), ("error", toString e)]
        badRequest s!"Failed to move card: {e}"

-- Reorder card (drag and drop)
page kanbanReorderCard "/kanban/card/:id/reorder" POST (id : Nat) do
  let ctx ← getCtx
  if !isLoggedIn ctx then return ← redirect "/login"
  let columnIdStr := ctx.paramD "column_id" ""
  let positionStr := ctx.paramD "position" "0"
  match columnIdStr.toNat?, positionStr.toNat? with
  | none, _ => badRequest "Invalid column ID"
  | _, none => badRequest "Invalid position"
  | some newColumnId, some position =>
    match ctx.database with
    | none => badRequest "Database not available"
    | some db =>
      let (oldColumnId, oldOrder) := match getCard ctx id with
        | some (card, colId) => (colId, card.order)
        | none => (0, 0)
      let cardEid : EntityId := ⟨id⟩
      let colEid : EntityId := ⟨newColumnId⟩
      let targetCards := getCardsForColumn db colEid
      let otherCards := targetCards.filter (·.id != id)
      let mut txOps : List TxOp := []
      txOps := txOps ++ DbCard.set_column db cardEid colEid
      let mut currentOrder := 0
      let mut insertedCard := false
      let mut idx := 0
      for card in otherCards do
        if idx == position && !insertedCard then
          txOps := txOps ++ DbCard.set_order db cardEid currentOrder
          currentOrder := currentOrder + 1
          insertedCard := true
        if card.order != currentOrder then
          txOps := txOps ++ DbCard.set_order db ⟨card.id⟩ currentOrder
        currentOrder := currentOrder + 1
        idx := idx + 1
      if !insertedCard then
        txOps := txOps ++ DbCard.set_order db cardEid currentOrder
      match ← transact txOps with
      | .ok () =>
        let ctx ← getCtx
        logAudit ctx "REORDER" "card" id [
          ("old_column_id", toString oldColumnId), ("new_column_id", toString newColumnId),
          ("old_position", toString oldOrder), ("new_position", toString position)
        ]
        let _ ← SSE.publishEvent "kanban" "card-reordered" (jsonStr! { "cardId" : id, "columnId" : newColumnId, position })
        html ""
      | .error e =>
        logAuditError ctx "REORDER" "card" [("card_id", toString id), ("error", toString e)]
        badRequest s!"Failed to reorder card: {e}"

end HomebaseApp.Pages
