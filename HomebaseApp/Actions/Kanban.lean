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
    let columnIds := db.entitiesWithAttr columnName
    columnIds.filterMap fun colId =>
      match db.getOne colId columnName, db.getOne colId columnOrder with
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

/-- Create a new column -/
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
    let tx : Transaction := [
      TxOp.add eid columnName (.string name),
      TxOp.add eid columnOrder (.int order)
    ]
    match ← ctx'.transact tx with
    | .ok ctx'' =>
      -- Return the new column HTML
      let col : Column := { id := eid.id.toNat, name := name, order := order.toNat, cards := [] }
      -- Need to also return the add column button after the new column
      let colHtml := Views.Kanban.renderColumnPartial ctx'' col
      let btnHtml := Views.Kanban.renderAddColumnButtonPartial
      -- Notify SSE clients about the new column
      let columnId := eid.id.toNat
      let _ ← SSE.publishEvent "kanban" "column-created" (jsonStr! { columnId, name })
      Action.html (colHtml ++ btnHtml) ctx''
    | .error e => Action.badRequest ctx' s!"Failed to create column: {e}"

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

/-- Update column -/
def updateColumn (columnId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let name := ctx.params.getD "name" ""
  if name.isEmpty then
    return ← Action.badRequest ctx "Column name is required"

  let tx : Transaction := [
    TxOp.add ⟨columnId⟩ columnName (.string name)
  ]
  match ← ctx.transact tx with
  | .ok ctx' =>
    match getColumn ctx' columnId with
    | none => Action.notFound ctx' "Column not found"
    | some col =>
      let html := Views.Kanban.renderColumnPartial ctx' col
      -- Notify SSE clients about the column update
      let _ ← SSE.publishEvent "kanban" "column-updated" (jsonStr! { columnId, name })
      Action.html html ctx'
  | .error e => Action.badRequest ctx s!"Failed to update column: {e}"

/-- Delete column and all its cards (uses generated retractionOps) -/
def deleteColumn (columnId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx

  match ctx.database with
  | none => Action.badRequest ctx "Database not available"
  | some db =>
    -- Get the column's cards to delete them
    let colId : EntityId := ⟨columnId⟩
    let cardIds := db.findByAttrValue DbCard.attr_column (.ref colId)

    -- Build retraction operations using generated helpers
    let mut txOps : List TxOp := []

    -- Retract each card's attributes using generated helper
    for cardId in cardIds do
      txOps := txOps ++ DbCard.retractionOps db cardId

    -- Retract column attributes using generated helper
    txOps := txOps ++ DbColumn.retractionOps db colId

    match ← ctx.transact txOps with
    | .ok ctx' =>
      -- Notify SSE clients about the column deletion
      let _ ← SSE.publishEvent "kanban" "column-deleted" (jsonStr! { columnId })
      -- Return empty string to remove from DOM
      Action.html "" ctx'
    | .error e => Action.badRequest ctx s!"Failed to delete column: {e}"

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
        let card := dbCard.toViewCard
        let html := Views.Kanban.renderCardPartial ctx'' card
        -- Notify SSE clients about the new card
        let cardId := eid.id.toNat
        let _ ← SSE.publishEvent "kanban" "card-created" (jsonStr! { cardId, columnId, title })
        Action.html html ctx''
      | .error e => Action.badRequest ctx' s!"Failed to create card: {e}"

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

/-- Update card -/
def updateCard (cardId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx
  let title := ctx.params.getD "title" ""
  let description := ctx.params.getD "description" ""
  let labels := ctx.params.getD "labels" ""

  if title.isEmpty then
    return ← Action.badRequest ctx "Card title is required"

  let tx : Transaction := [
    TxOp.add ⟨cardId⟩ cardTitle (.string title),
    TxOp.add ⟨cardId⟩ cardDescription (.string description),
    TxOp.add ⟨cardId⟩ cardLabels (.string labels)
  ]
  match ← ctx.transact tx with
  | .ok ctx' =>
    match getCard ctx' cardId with
    | none => Action.notFound ctx' "Card not found"
    | some (card, _) =>
      let html := Views.Kanban.renderCardPartial ctx' card
      -- Notify SSE clients about the card update
      let _ ← SSE.publishEvent "kanban" "card-updated" (jsonStr! { cardId, title })
      Action.html html ctx'
  | .error e => Action.badRequest ctx s!"Failed to update card: {e}"

/-- Delete card (uses generated DbCard.retractionOps) -/
def deleteCard (cardId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx

  match ctx.database with
  | none => Action.badRequest ctx "Database not available"
  | some db =>
    let eid : EntityId := ⟨cardId⟩
    -- Use generated retractionOps helper
    let txOps := DbCard.retractionOps db eid

    match ← ctx.transact txOps with
    | .ok ctx' =>
      -- Notify SSE clients about the card deletion
      let _ ← SSE.publishEvent "kanban" "card-deleted" (jsonStr! { cardId })
      -- Return empty string to remove from DOM
      Action.html "" ctx'
    | .error e => Action.badRequest ctx s!"Failed to delete card: {e}"

/-- Move card to another column -/
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
      let cardEid : EntityId := ⟨cardId⟩
      -- Get the card's current column to retract it
      match db.getOne cardEid cardColumn with
      | none => Action.notFound ctx "Card not found"
      | some oldColumnRef =>
        -- Get next order in the target column
        let order := getNextCardOrder ctx newColumnId
        -- Retract old column reference, then add new one
        let tx : Transaction := [
          TxOp.retract cardEid cardColumn oldColumnRef,
          TxOp.add cardEid cardColumn (.ref ⟨newColumnId⟩),
          TxOp.add cardEid cardOrder (.int order)
        ]
        match ← ctx.transact tx with
        | .ok ctx' =>
          match getCard ctx' cardId with
          | none => Action.notFound ctx' "Card not found"
          | some (card, _) =>
            let html := Views.Kanban.renderCardPartial ctx' card
            -- Notify SSE clients about the card move
            let _ ← SSE.publishEvent "kanban" "card-moved" (jsonStr! { cardId, newColumnId })
            Action.html html ctx'
        | .error e => Action.badRequest ctx s!"Failed to move card: {e}"

/-- Reorder card (drag and drop) - handles both within-column and cross-column moves -/
def reorderCard (cardId : Nat) : Action := fun ctx => do
  if !isLoggedIn ctx then
    return ← Action.redirect "/login" ctx

  let columnIdStr := ctx.params.getD "column_id" ""
  let positionStr := ctx.params.getD "position" "0"

  IO.println s!"[reorderCard] cardId={cardId} column_id={columnIdStr} position={positionStr}"

  match columnIdStr.toNat?, positionStr.toNat? with
  | none, _ => Action.badRequest ctx "Invalid column ID"
  | _, none => Action.badRequest ctx "Invalid position"
  | some newColumnId, some position =>
    match ctx.database with
    | none => Action.badRequest ctx "Database not available"
    | some db =>
      -- Get the current card info
      let cardEid : EntityId := ⟨cardId⟩
      let colEid : EntityId := ⟨newColumnId⟩

      IO.println s!"[reorderCard] cardEid={cardEid.id} colEid={colEid.id}"

      -- Get all cards in the target column (excluding the moved card)
      let targetCards := getCardsForColumn db colEid
      let otherCards := targetCards.filter (·.id != cardId)

      IO.println s!"[reorderCard] targetCards={targetCards.length} otherCards={otherCards.length}"

      -- Build transaction operations
      let mut txOps : List TxOp := []

      -- Get the card's current column
      match db.getOne cardEid cardColumn with
      | none => return ← Action.notFound ctx "Card not found"
      | some oldColumnRef =>
        -- Only update column reference if it's actually changing
        if oldColumnRef != Value.ref colEid then
          txOps := TxOp.retract cardEid cardColumn oldColumnRef :: txOps
          txOps := TxOp.add cardEid cardColumn (.ref colEid) :: txOps

      -- Calculate new order values
      -- Position the moved card at 'position', shift others accordingly
      let mut currentOrder := 0
      let mut insertedCard := false
      let mut idx := 0

      for card in otherCards do
        -- Insert the moved card at the target position
        if idx == position && !insertedCard then
          txOps := TxOp.add cardEid cardOrder (.int currentOrder) :: txOps
          currentOrder := currentOrder + 1
          insertedCard := true

        -- Update existing card's order
        if card.order != currentOrder.toNat then
          txOps := TxOp.add ⟨card.id⟩ cardOrder (.int currentOrder) :: txOps
        currentOrder := currentOrder + 1
        idx := idx + 1

      -- If position is at the end (or beyond), add moved card at end
      if !insertedCard then
        txOps := TxOp.add cardEid cardOrder (.int currentOrder) :: txOps

      IO.println s!"[reorderCard] txOps count={txOps.length}"

      match ← ctx.transact txOps with
      | .ok ctx' =>
        IO.println s!"[reorderCard] Transaction succeeded"
        -- Notify SSE clients about the card reorder
        let _ ← SSE.publishEvent "kanban" "card-reordered" (jsonStr! { cardId, "columnId" : newColumnId, position })
        -- Return empty response - the DOM is already updated by SortableJS
        Action.html "" ctx'
      | .error e =>
        IO.println s!"[reorderCard] Transaction failed: {e}"
        Action.badRequest ctx s!"Failed to reorder card: {e}"

end HomebaseApp.Actions.Kanban
