/-
  HomebaseApp.Actions.Kanban - Kanban board CRUD actions
-/
import Loom
import Ledger
import HomebaseApp.Helpers
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Views.Kanban

namespace HomebaseApp.Actions.Kanban

open Loom
open Loom.Json
open Ledger
open HomebaseApp.Helpers
open HomebaseApp.Models
open HomebaseApp.Entities
open HomebaseApp.Views.Kanban

-- Helper to get all columns from database
def getColumns (ctx : Context) : List (EntityId × String × Int) :=
  match ctx.database with
  | none => []
  | some db =>
    -- Find all entities with column/name attribute
    let columnIds := db.entitiesWithAttr DbColumn.attr_name
    columnIds.filterMap fun colId =>
      match db.getOne colId DbColumn.attr_name, db.getOne colId DbColumn.attr_order with
      | some (.string name), some (.int order) => some (colId, name, order)
      | _, _ => none

-- Helper to get cards for a column (uses generated DbCard.pull)
def getCardsForColumn (db : Db) (colId : EntityId) : List Card :=
  let cardIds := db.findByAttrValue DbCard.attr_column (.ref colId)
  let cards := cardIds.filterMap fun cardId =>
    -- Verify the card's CURRENT column is this column (filter out historical references)
    match DbCard.pull db cardId with
    | some dbCard =>
      if dbCard.column != colId then none
      else some (dbCard.toViewCard)
    | none => none
  -- Sort by order
  cards.toArray.qsort (fun a b => a.order < b.order) |>.toList

-- Helper to get all columns with their cards from database
def getColumnsWithCards (ctx : Context) : List Column :=
  match ctx.database with
  | none => []
  | some db =>
    let rawColumns := getColumns ctx
    let columns := rawColumns.map fun (colId, name, order) =>
      let cards := getCardsForColumn db colId
      { id := colId.id.toNat, name := name, order := order.toNat, cards := cards }
    -- Sort by order
    columns.toArray.qsort (fun a b => a.order < b.order) |>.toList

-- Helper to get a single column by ID
def getColumn (ctx : Context) (columnId : Nat) : Option Column :=
  let columns := getColumnsWithCards ctx
  columns.find? (·.id == columnId)

-- Helper to get a single card by ID (uses generated DbCard.pull)
def getCard (ctx : Context) (cardId : Nat) : Option (Card × Nat) := -- Returns card and column ID
  match ctx.database with
  | none => none
  | some db =>
    let eid : EntityId := ⟨cardId⟩
    match DbCard.pull db eid with
    | some dbCard => some (dbCard.toViewCard, dbCard.column.id.toNat)
    | none => none

-- Helper to get next order value for columns
def getNextColumnOrder (ctx : Context) : Int :=
  let columns := getColumns ctx
  match columns.map (fun (_, _, order) => order) with
  | [] => 0
  | orders => orders.foldl max 0 + 1

-- Helper to get next order value for cards in a column
def getNextCardOrder (ctx : Context) (columnId : Nat) : Int :=
  match getColumn ctx columnId with
  | some col =>
    match col.cards.map (·.order) with
    | [] => 0
    | orders => (orders.foldl max 0 : Nat) + 1
  | none => 0

-- ============================================================================
-- Main page
-- ============================================================================

def index : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let columns := getColumnsWithCards ctx
  let html := Views.Kanban.render ctx columns
  Action.html html ctx

-- ============================================================================
-- Column actions
-- ============================================================================

/-- Show add column form (HTMX partial) -/
def addColumnForm : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := Views.Kanban.renderAddColumnFormPartial ctx
  Action.html html ctx

/-- Show add column button (HTMX partial) -/
def addColumnButton : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := Views.Kanban.renderAddColumnButtonPartial
  Action.html html ctx

/-- Get all columns (HTMX partial for SSE refresh) -/
def columns : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let columns := getColumnsWithCards ctx
  let html := Views.Kanban.renderColumnsPartial ctx columns
  Action.html html ctx

/-- Create a new column (uses generated DbColumn.createOps) -/
def createColumn : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let name := ctx.params.getD "name" ""
  if name.isEmpty then
    return ← Action.badRequest ctx "Column name is required"

  -- Allocate entity ID and create column
  match ctx.allocEntityId with
  | none => Action.badRequest ctx "Database not available"
  | some (eid, ctx') =>
    let order := getNextColumnOrder ctx'
    let dbCol : DbColumn := { id := eid.id.toNat, name := name, order := order.toNat }
    let tx := DbColumn.createOps eid dbCol
    match ← ctx'.transact tx with
    | .ok ctx'' =>
      -- Audit log
      logAudit ctx'' "CREATE" "column" eid.id.toNat [("name", name)]
      -- Return the new column HTML
      let col : Column := { id := eid.id.toNat, name := name, order := order.toNat, cards := [] }
      -- Need to also return the add column button after the new column
      let colHtml := Views.Kanban.renderColumnPartial ctx'' col
      let btnHtml := Views.Kanban.renderAddColumnButtonPartial
      -- Notify SSE clients about the new column
      let columnId := eid.id.toNat
      let _ ← SSE.publishEvent "kanban" "column-created" (jsonStr! { columnId, name })
      Action.html (colHtml ++ btnHtml) ctx''
    | .error e =>
      logAuditError ctx "CREATE" "column" [("name", name), ("error", toString e)]
      Action.badRequest ctx' s!"Failed to create column: {e}"

/-- Get column (HTMX partial for refresh) -/
def getColumnPartial (columnId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  match getColumn ctx columnId with
  | none => Action.notFound ctx "Column not found"
  | some col =>
    let html := Views.Kanban.renderColumnPartial ctx col
    Action.html html ctx

/-- Show column edit form -/
def editColumnForm (columnId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  match getColumn ctx columnId with
  | none => Action.notFound ctx "Column not found"
  | some col =>
    let html := Views.Kanban.renderColumnEditFormPartial ctx col
    Action.html html ctx

/-- Update column (uses generated set_name with cardinality-one enforcement) -/
def updateColumn (columnId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let name := ctx.params.getD "name" ""
  if name.isEmpty then
    return ← Action.badRequest ctx "Column name is required"

  match ctx.database with
  | none => Action.badRequest ctx "Database not available"
  | some db =>
    -- Capture old name for audit
    let oldName := match getColumn ctx columnId with
      | some col => col.name
      | none => "(unknown)"
    let tx := DbColumn.set_name db ⟨columnId⟩ name
    match ← ctx.transact tx with
    | .ok ctx' =>
      match getColumn ctx' columnId with
      | none => Action.notFound ctx' "Column not found"
      | some col =>
        -- Audit log with old/new values
        logAudit ctx' "UPDATE" "column" columnId [("old_name", oldName), ("new_name", name)]
        let html := Views.Kanban.renderColumnPartial ctx' col
        -- Notify SSE clients about the column update
        let _ ← SSE.publishEvent "kanban" "column-updated" (jsonStr! { columnId, name })
        Action.html html ctx'
    | .error e =>
      logAuditError ctx "UPDATE" "column" [("column_id", toString columnId), ("error", toString e)]
      Action.badRequest ctx s!"Failed to update column: {e}"

/-- Delete column and all its cards (uses generated retractionOps) -/
def deleteColumn (columnId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx

  match ctx.database with
  | none => Action.badRequest ctx "Database not available"
  | some db =>
    -- Capture column info for audit before deletion
    let columnName := match getColumn ctx columnId with
      | some col => col.name
      | none => "(unknown)"

    -- Get the column's cards to delete them
    let colId : EntityId := ⟨columnId⟩
    let cardIds := db.findByAttrValue DbCard.attr_column (.ref colId)
    let cardCount := cardIds.length

    -- Build retraction operations using generated helpers
    let mut txOps : List TxOp := []

    -- Retract each card's attributes using generated helper
    for cardId in cardIds do
      txOps := txOps ++ DbCard.retractionOps db cardId

    -- Retract column attributes using generated helper
    txOps := txOps ++ DbColumn.retractionOps db colId

    match ← ctx.transact txOps with
    | .ok ctx' =>
      -- Audit log with cascade info
      logAudit ctx' "DELETE" "column" columnId [("name", columnName), ("cascade_cards", toString cardCount)]
      -- Notify SSE clients about the column deletion
      let _ ← SSE.publishEvent "kanban" "column-deleted" (jsonStr! { columnId })
      -- Return empty string to remove from DOM
      Action.html "" ctx'
    | .error e =>
      logAuditError ctx "DELETE" "column" [("column_id", toString columnId), ("error", toString e)]
      Action.badRequest ctx s!"Failed to delete column: {e}"

-- ============================================================================
-- Card actions
-- ============================================================================

/-- Show add card form for a column -/
def addCardForm (columnId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := Views.Kanban.renderAddCardFormPartial ctx columnId
  Action.html html ctx

/-- Show add card button for a column -/
def addCardButton (columnId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let html := Views.Kanban.renderAddCardButtonPartial columnId
  Action.html html ctx

/-- Create a new card (uses generated DbCard.createOps) -/
def createCard : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let title := ctx.params.getD "title" ""
  let description := ctx.params.getD "description" ""
  let labels := ctx.params.getD "labels" ""
  let columnIdStr := ctx.params.getD "column_id" ""

  if title.isEmpty then
    return ← Action.badRequest ctx "Card title is required"

  match columnIdStr.toNat? with
  | none => Action.badRequest ctx "Invalid column ID"
  | some columnId =>
    match ctx.allocEntityId with
    | none => Action.badRequest ctx "Database not available"
    | some (eid, ctx') =>
      let order := getNextCardOrder ctx' columnId
      -- Use generated createOps helper
      let dbCard : DbCard := {
        id := eid.id.toNat
        title := title
        description := description
        labels := labels
        order := order.toNat
        column := ⟨columnId⟩
      }
      let tx := DbCard.createOps eid dbCard
      match ← ctx'.transact tx with
      | .ok ctx'' =>
        -- Audit log
        logAudit ctx'' "CREATE" "card" eid.id.toNat [("title", title), ("column_id", toString columnId)]
        let card := dbCard.toViewCard
        let html := Views.Kanban.renderCardPartial ctx'' card
        -- Notify SSE clients about the new card
        let cardId := eid.id.toNat
        let _ ← SSE.publishEvent "kanban" "card-created" (jsonStr! { cardId, columnId, title })
        Action.html html ctx''
      | .error e =>
        logAuditError ctx "CREATE" "card" [("title", title), ("error", toString e)]
        Action.badRequest ctx' s!"Failed to create card: {e}"

/-- Get card (HTMX partial for refresh) -/
def getCardPartial (cardId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  match getCard ctx cardId with
  | none => Action.notFound ctx "Card not found"
  | some (card, _) =>
    let html := Views.Kanban.renderCardPartial ctx card
    Action.html html ctx

/-- Show card edit form -/
def editCardForm (cardId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  match getCard ctx cardId with
  | none => Action.notFound ctx "Card not found"
  | some (card, _) =>
    let html := Views.Kanban.renderCardEditFormPartial ctx card
    Action.html html ctx

/-- Update card (uses generated setters with cardinality-one enforcement) -/
def updateCard (cardId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let title := ctx.params.getD "title" ""
  let description := ctx.params.getD "description" ""
  let labels := ctx.params.getD "labels" ""

  if title.isEmpty then
    return ← Action.badRequest ctx "Card title is required"

  match ctx.database with
  | none => Action.badRequest ctx "Database not available"
  | some db =>
    -- Capture old values for audit
    let (oldTitle, oldDesc, oldLabels) := match getCard ctx cardId with
      | some (card, _) => (card.title, card.description, card.labels)
      | none => ("", "", "")
    let eid : EntityId := ⟨cardId⟩
    let tx := DbCard.set_title db eid title ++
              DbCard.set_description db eid description ++
              DbCard.set_labels db eid labels
    match ← ctx.transact tx with
    | .ok ctx' =>
      match getCard ctx' cardId with
      | none => Action.notFound ctx' "Card not found"
      | some (card, _) =>
        -- Audit log with changed fields
        let mut changes : List (String × String) := []
        if oldTitle != title then changes := changes ++ [("old_title", oldTitle), ("new_title", title)]
        if oldDesc != description then changes := changes ++ [("description_changed", "true")]
        if oldLabels != labels then changes := changes ++ [("old_labels", oldLabels), ("new_labels", labels)]
        logAudit ctx' "UPDATE" "card" cardId changes
        let html := Views.Kanban.renderCardPartial ctx' card
        -- Notify SSE clients about the card update
        let _ ← SSE.publishEvent "kanban" "card-updated" (jsonStr! { cardId, title })
        Action.html html ctx'
    | .error e =>
      logAuditError ctx "UPDATE" "card" [("card_id", toString cardId), ("error", toString e)]
      Action.badRequest ctx s!"Failed to update card: {e}"

/-- Delete card (uses generated DbCard.retractionOps) -/
def deleteCard (cardId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx

  match ctx.database with
  | none => Action.badRequest ctx "Database not available"
  | some db =>
    -- Capture card info for audit before deletion
    let (cardTitle, columnId) := match getCard ctx cardId with
      | some (card, colId) => (card.title, colId)
      | none => ("(unknown)", 0)
    let eid : EntityId := ⟨cardId⟩
    -- Use generated retractionOps helper
    let txOps := DbCard.retractionOps db eid

    match ← ctx.transact txOps with
    | .ok ctx' =>
      -- Audit log
      logAudit ctx' "DELETE" "card" cardId [("title", cardTitle), ("column_id", toString columnId)]
      -- Notify SSE clients about the card deletion
      let _ ← SSE.publishEvent "kanban" "card-deleted" (jsonStr! { cardId })
      -- Return empty string to remove from DOM
      Action.html "" ctx'
    | .error e =>
      logAuditError ctx "DELETE" "card" [("card_id", toString cardId), ("error", toString e)]
      Action.badRequest ctx s!"Failed to delete card: {e}"

/-- Move card to another column (uses generated setters with cardinality-one enforcement) -/
def moveCard (cardId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx

  let columnIdStr := ctx.params.getD "column_id" ""
  match columnIdStr.toNat? with
  | none => Action.badRequest ctx "Invalid column ID"
  | some newColumnId =>
    match ctx.database with
    | none => Action.badRequest ctx "Database not available"
    | some db =>
      -- Capture old column for audit
      let oldColumnId := match getCard ctx cardId with
        | some (_, colId) => colId
        | none => 0
      let cardEid : EntityId := ⟨cardId⟩
      -- Get next order in the target column
      let order := getNextCardOrder ctx newColumnId
      -- Use generated setters (handles retraction automatically)
      let tx := DbCard.set_column db cardEid ⟨newColumnId⟩ ++
                DbCard.set_order db cardEid order.toNat
      match ← ctx.transact tx with
      | .ok ctx' =>
        match getCard ctx' cardId with
        | none => Action.notFound ctx' "Card not found"
        | some (card, _) =>
          -- Audit log with old/new column
          logAudit ctx' "MOVE" "card" cardId [("old_column_id", toString oldColumnId), ("new_column_id", toString newColumnId)]
          let html := Views.Kanban.renderCardPartial ctx' card
          -- Notify SSE clients about the card move
          let _ ← SSE.publishEvent "kanban" "card-moved" (jsonStr! { cardId, newColumnId })
          Action.html html ctx'
      | .error e =>
        logAuditError ctx "MOVE" "card" [("card_id", toString cardId), ("error", toString e)]
        Action.badRequest ctx s!"Failed to move card: {e}"

/-- Reorder card (drag and drop) - handles both within-column and cross-column moves
    Uses generated setters with cardinality-one enforcement -/
def reorderCard (cardId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx

  let columnIdStr := ctx.params.getD "column_id" ""
  let positionStr := ctx.params.getD "position" "0"

  match columnIdStr.toNat?, positionStr.toNat? with
  | none, _ => Action.badRequest ctx "Invalid column ID"
  | _, none => Action.badRequest ctx "Invalid position"
  | some newColumnId, some position =>
    match ctx.database with
    | none => Action.badRequest ctx "Database not available"
    | some db =>
      -- Capture old position for audit
      let (oldColumnId, oldOrder) := match getCard ctx cardId with
        | some (card, colId) => (colId, card.order)
        | none => (0, 0)

      -- Get the current card info
      let cardEid : EntityId := ⟨cardId⟩
      let colEid : EntityId := ⟨newColumnId⟩

      -- Get all cards in the target column (excluding the moved card)
      let targetCards := getCardsForColumn db colEid
      let otherCards := targetCards.filter (·.id != cardId)

      -- Build transaction operations using generated setters
      let mut txOps : List TxOp := []

      -- Update column reference using generated setter (handles retraction automatically)
      txOps := txOps ++ DbCard.set_column db cardEid colEid

      -- Calculate new order values
      -- Position the moved card at 'position', shift others accordingly
      let mut currentOrder := 0
      let mut insertedCard := false
      let mut idx := 0

      for card in otherCards do
        -- Insert the moved card at the target position
        if idx == position && !insertedCard then
          txOps := txOps ++ DbCard.set_order db cardEid currentOrder
          currentOrder := currentOrder + 1
          insertedCard := true

        -- Update existing card's order using generated setter
        if card.order != currentOrder then
          txOps := txOps ++ DbCard.set_order db ⟨card.id⟩ currentOrder
        currentOrder := currentOrder + 1
        idx := idx + 1

      -- If position is at the end (or beyond), add moved card at end
      if !insertedCard then
        txOps := txOps ++ DbCard.set_order db cardEid currentOrder

      match ← ctx.transact txOps with
      | .ok ctx' =>
        -- Audit log with position info
        logAudit ctx' "REORDER" "card" cardId [
          ("old_column_id", toString oldColumnId),
          ("new_column_id", toString newColumnId),
          ("old_position", toString oldOrder),
          ("new_position", toString position)
        ]
        -- Notify SSE clients about the card reorder
        let _ ← SSE.publishEvent "kanban" "card-reordered" (jsonStr! { cardId, "columnId" : newColumnId, position })
        -- Return empty response - the DOM is already updated by SortableJS
        Action.html "" ctx'
      | .error e =>
        logAuditError ctx "REORDER" "card" [("card_id", toString cardId), ("error", toString e)]
        Action.badRequest ctx s!"Failed to reorder card: {e}"

end HomebaseApp.Actions.Kanban
