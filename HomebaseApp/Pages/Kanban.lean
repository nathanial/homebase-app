/-
  HomebaseApp.Pages.Kanban - Kanban board pages
-/
import Scribe
import Loom
import Loom.Stencil
import Stencil
import Ledger
import HomebaseApp.Shared
import HomebaseApp.StencilHelpers
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
open HomebaseApp.StencilHelpers
-- Note: Use fully qualified middleware names in page/view/action macros
-- because #generate_pages creates code in a separate elaboration context

/-! ## Data Structures -/

structure Board where
  id : Nat
  name : String
  order : Nat
  deriving Inhabited

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

/-- Get all boards from the database -/
def getBoards (ctx : Context) : List Board :=
  match ctx.database with
  | none => []
  | some db =>
    let boardIds := db.entitiesWithAttr DbBoard.attr_name
    let boards := boardIds.filterMap fun boardId =>
      match DbBoard.pull db boardId with
      | some b => some { id := b.id, name := b.name, order := b.order }
      | none => none
    boards.toArray.qsort (fun a b => a.order < b.order) |>.toList

/-- Get a specific board by ID -/
def getBoard (ctx : Context) (boardId : Nat) : Option Board :=
  (getBoards ctx).find? (·.id == boardId)

/-- Get the next order value for a new board -/
def getNextBoardOrder (ctx : Context) : Nat :=
  match (getBoards ctx).map (·.order) with
  | [] => 0
  | orders => orders.foldl max 0 + 1

/-- Get columns for a specific board -/
def getColumnsForBoard (ctx : Context) (boardId : Nat) : List (EntityId × String × Int) :=
  match ctx.database with
  | none => []
  | some db =>
    let boardEid : EntityId := ⟨boardId⟩
    let columnIds := db.findByAttrValue DbColumn.attr_board (.ref boardEid)
    columnIds.filterMap fun colId =>
      match db.getOne colId DbColumn.attr_name, db.getOne colId DbColumn.attr_order with
      | some (.string name), some (.int order) => some (colId, name, order)
      | _, _ => none

/-- Get all columns (for backward compatibility, finds orphans) -/
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

/-- Get columns with their cards for a specific board -/
def getColumnsWithCardsForBoard (ctx : Context) (boardId : Nat) : List Column :=
  match ctx.database with
  | none => []
  | some db =>
    let rawColumns := getColumnsForBoard ctx boardId
    let columns := rawColumns.map fun (colId, name, order) =>
      let cards := getCardsForColumn db colId
      { id := colId.id.toNat, name := name, order := order.toNat, cards := cards }
    columns.toArray.qsort (fun a b => a.order < b.order) |>.toList

/-- Get all columns with cards (for backward compatibility) -/
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

def getNextColumnOrder (ctx : Context) (boardId : Nat) : Int :=
  let columns := getColumnsForBoard ctx boardId
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

/-! ## Stencil Value Helpers -/

def labelClass (label : String) : String :=
  match label.trim.toLower with
  | "bug" => "label-bug"
  | "feature" => "label-feature"
  | "urgent" => "label-urgent"
  | "low" => "label-low"
  | "high" => "label-high"
  | "blocked" => "label-blocked"
  | _ => "label-default"

/-- Convert a label string to Stencil.Value with its class -/
def labelToValue (label : String) : Stencil.Value :=
  .object #[
    ("label", .string label.trim),
    ("labelClass", .string (labelClass label))
  ]

/-- Convert a card to Stencil.Value -/
def cardToValue (card : Card) : Stencil.Value :=
  let labels := card.labels.splitOn "," |>.filter (fun s => !s.trim.isEmpty)
  .object #[
    ("id", .int (Int.ofNat card.id)),
    ("title", .string card.title),
    ("description", .string card.description),
    ("labelsStr", .string card.labels),
    ("hasLabels", .bool (!labels.isEmpty)),
    ("labels", .array (labels.map labelToValue).toArray),
    ("hasDescription", .bool (!card.description.isEmpty)),
    ("order", .int (Int.ofNat card.order))
  ]

/-- Convert a column to Stencil.Value -/
def columnToValue (col : Column) : Stencil.Value :=
  .object #[
    ("id", .int (Int.ofNat col.id)),
    ("name", .string col.name),
    ("order", .int (Int.ofNat col.order)),
    ("cards", .array (col.cards.map cardToValue).toArray)
  ]

/-- Convert a board to Stencil.Value -/
def boardToValue (board : Board) (isActive : Bool) : Stencil.Value :=
  .object #[
    ("id", .int (Int.ofNat board.id)),
    ("name", .string board.name),
    ("order", .int (Int.ofNat board.order)),
    ("isActive", .bool isActive)
  ]

/-- Build kanban page data for Stencil -/
def kanbanPageData (ctx : Context) (boards : List Board) (activeBoard : Board) (columns : List Column) : Stencil.Value :=
  .object #[
    ("boards", .array (boards.map fun b => boardToValue b (b.id == activeBoard.id)).toArray),
    ("activeBoard", boardToValue activeBoard true),
    ("columns", .array (columns.map columnToValue).toArray),
    ("columnCount", .int (Int.ofNat columns.length)),
    ("csrfToken", .string ctx.csrfToken)
  ]

/-! ## Pages -/

-- Main kanban board - redirects to first board or creates default
action kanban "/kanban" GET [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let boards := getBoards ctx
  match boards.head? with
  | some board => redirect s!"/kanban/board/{board.id}"
  | none =>
    -- Auto-create "Default" board
    let (eid, _) ← withNewEntityAudit! fun eid => do
      let dbBoard : DbBoard := { id := eid.id.toNat, name := "Default", order := 0 }
      DbBoard.TxM.create eid dbBoard
      audit "CREATE" "board" eid.id.toNat [("name", "Default"), ("auto_created", "true")]
    -- Migrate any orphan columns to the new board
    let ctx ← getCtx
    let orphanColumns := getColumns ctx
    if !orphanColumns.isEmpty then
      runAuditTx! do
        for (colId, _, _) in orphanColumns do
          DbColumn.TxM.setBoard colId eid
        audit "MIGRATE" "columns" eid.id.toNat [("count", toString orphanColumns.length)]
    redirect s!"/kanban/board/{eid.id.toNat}"

-- View specific board
view kanbanBoard "/kanban/board/:boardId" [HomebaseApp.Middleware.authRequired] (boardId : Nat) do
  let ctx ← getCtx
  let boards := getBoards ctx
  match getBoard ctx boardId with
  | none => notFound "Board not found"
  | some board =>
    let columns := getColumnsWithCardsForBoard ctx boardId
    let data := pageContext ctx s!"{board.name} - Kanban" PageId.kanban (kanbanPageData ctx boards board columns)
    Loom.Stencil.ActionM.renderWithLayout "app" "kanban/index" data

-- Get all columns for a board (for SSE refresh)
view kanbanBoardColumns "/kanban/board/:boardId/columns" [HomebaseApp.Middleware.authRequired] (boardId : Nat) do
  let ctx ← getCtx
  let columns := getColumnsWithCardsForBoard ctx boardId
  let data := Stencil.Value.object #[
    ("columns", .array (columns.map columnToValue).toArray)
  ]
  Loom.Stencil.ActionM.render "kanban/board-columns" data

-- Note: SSE endpoint "/events/kanban" is registered separately in Main.lean

-- Add board form
view kanbanAddBoardForm "/kanban/add-board-form" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let data := Stencil.Value.object #[("csrfToken", .string ctx.csrfToken)]
  Loom.Stencil.ActionM.render "kanban/add-board" data

-- Create board
action kanbanCreateBoard "/kanban/board" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let name := ctx.paramD "name" ""
  if name.isEmpty then return ← badRequest "Board name is required"
  let ctx ← getCtx
  let order := getNextBoardOrder ctx
  let (eid, _) ← withNewEntityAudit! fun eid => do
    let dbBoard : DbBoard := { id := eid.id.toNat, name := name, order := order }
    DbBoard.TxM.create eid dbBoard
    audit "CREATE" "board" eid.id.toNat [("name", name)]
  let _ ← SSE.publishEvent "kanban" "board-created" (jsonStr! { "boardId" : eid.id.toNat, name })
  -- Redirect to the new board
  redirect s!"/kanban/board/{eid.id.toNat}"

-- Edit board form
view kanbanEditBoardForm "/kanban/board/:boardId/edit" [HomebaseApp.Middleware.authRequired] (boardId : Nat) do
  let ctx ← getCtx
  match getBoard ctx boardId with
  | none => notFound "Board not found"
  | some board =>
    let data := mergeContext (boardToValue board false)
      (.object #[("csrfToken", .string ctx.csrfToken)])
    Loom.Stencil.ActionM.render "kanban/edit-board" data

-- Update board
action kanbanUpdateBoard "/kanban/board/:boardId" PUT [HomebaseApp.Middleware.authRequired] (boardId : Nat) do
  let ctx ← getCtx
  let name := ctx.paramD "name" ""
  if name.isEmpty then return ← badRequest "Board name is required"
  let oldName := match getBoard ctx boardId with
    | some b => b.name
    | none => "(unknown)"
  let eid : EntityId := ⟨boardId⟩
  runAuditTx! do
    DbBoard.TxM.setName eid name
    audit "UPDATE" "board" boardId [("old_name", oldName), ("new_name", name)]
  let _ ← SSE.publishEvent "kanban" "board-updated" (jsonStr! { "boardId" : boardId, name })
  html ""

-- Delete board (cascade delete columns and cards)
action kanbanDeleteBoard "/kanban/board/:boardId" DELETE [HomebaseApp.Middleware.authRequired] (boardId : Nat) do
  let ctx ← getCtx
  let some db := ctx.database | return ← badRequest "Database not available"
  let boardName := match getBoard ctx boardId with
    | some b => b.name
    | none => "(unknown)"
  let boardEid : EntityId := ⟨boardId⟩
  -- Get all columns for this board
  let columnIds := db.findByAttrValue DbColumn.attr_board (.ref boardEid)
  -- Get all cards for these columns
  let allCardIds := columnIds.foldl (init := []) fun acc colId =>
    acc ++ db.findByAttrValue DbCard.attr_column (.ref colId)
  let columnCount := columnIds.length
  let cardCount := allCardIds.length
  runAuditTx! do
    -- Delete all cards
    for cardId in allCardIds do
      DbCard.TxM.delete cardId
    -- Delete all columns
    for colId in columnIds do
      DbColumn.TxM.delete colId
    -- Delete the board
    DbBoard.TxM.delete boardEid
    audit "DELETE" "board" boardId [
      ("name", boardName),
      ("cascade_columns", toString columnCount),
      ("cascade_cards", toString cardCount)
    ]
  let _ ← SSE.publishEvent "kanban" "board-deleted" (jsonStr! { "boardId" : boardId })
  -- Redirect to /kanban (will auto-create default if needed)
  redirect "/kanban"

-- Add column form (board-aware)
view kanbanAddColumnFormForBoard "/kanban/board/:boardId/add-column-form" [HomebaseApp.Middleware.authRequired] (boardId : Nat) do
  let ctx ← getCtx
  let data := Stencil.Value.object #[
    ("boardId", .int (Int.ofNat boardId)),
    ("csrfToken", .string ctx.csrfToken)
  ]
  Loom.Stencil.ActionM.render "kanban/add-column" data

-- Create column (board-aware)
action kanbanCreateColumnForBoard "/kanban/board/:boardId/column" POST [HomebaseApp.Middleware.authRequired] (boardId : Nat) do
  let ctx ← getCtx
  let name := ctx.paramD "name" ""
  if name.isEmpty then return ← badRequest "Column name is required"
  let ctx ← getCtx
  let order := getNextColumnOrder ctx boardId
  let boardEid : EntityId := ⟨boardId⟩
  let (eid, _) ← withNewEntityAudit! fun eid => do
    let dbCol : DbColumn := { id := eid.id.toNat, name := name, order := order.toNat, board := boardEid }
    DbColumn.TxM.create eid dbCol
    audit "CREATE" "column" eid.id.toNat [("name", name), ("board_id", toString boardId)]
  let _ ← SSE.publishEvent "kanban" "column-created" (jsonStr! { "columnId" : eid.id.toNat, "boardId" : boardId, name })
  html ""

-- Add column form (legacy - kept for backward compatibility)
view kanbanAddColumnForm "/kanban/add-column-form" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  -- Get the first board for legacy route
  let boards := getBoards ctx
  let boardId := match boards.head? with
    | some b => b.id
    | none => 0
  let data := Stencil.Value.object #[
    ("boardId", .int (Int.ofNat boardId)),
    ("csrfToken", .string ctx.csrfToken)
  ]
  Loom.Stencil.ActionM.render "kanban/add-column" data

-- Create column
action kanbanCreateColumn "/kanban/column" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let name := ctx.paramD "name" ""
  if name.isEmpty then return ← badRequest "Column name is required"
  -- Get the first board (legacy route - new code should use board-specific route)
  let boards := getBoards ctx
  let some board := boards.head? | return ← badRequest "No board exists"
  let boardEid : EntityId := ⟨board.id⟩
  let ctx ← getCtx
  let order := getNextColumnOrder ctx board.id
  let (eid, _) ← withNewEntityAudit! fun eid => do
    let dbCol : DbColumn := { id := eid.id.toNat, name := name, order := order.toNat, board := boardEid }
    DbColumn.TxM.create eid dbCol
    audit "CREATE" "column" eid.id.toNat [("name", name), ("board_id", toString board.id)]
  let _ ← SSE.publishEvent "kanban" "column-created" (jsonStr! { "columnId" : eid.id.toNat, "boardId" : board.id, name })
  html ""

-- Get column
view kanbanGetColumn "/kanban/column/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getColumn ctx id with
  | none => notFound "Column not found"
  | some col => Loom.Stencil.ActionM.renderPartial "kanban/_column" (columnToValue col)

-- Edit column form
view kanbanEditColumnForm "/kanban/column/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getColumn ctx id with
  | none => notFound "Column not found"
  | some col =>
    let data := mergeContext (columnToValue col)
      (.object #[("csrfToken", .string ctx.csrfToken)])
    Loom.Stencil.ActionM.render "kanban/edit-column" data

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
  let data := Stencil.Value.object #[
    ("columnId", .int (Int.ofNat columnId)),
    ("csrfToken", .string ctx.csrfToken)
  ]
  Loom.Stencil.ActionM.render "kanban/add-card" data

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
  | some (card, _) => Loom.Stencil.ActionM.renderPartial "kanban/_card" (cardToValue card)

-- Edit card form
view kanbanEditCardForm "/kanban/card/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getCard ctx id with
  | none => notFound "Card not found"
  | some (card, _) =>
    let data := mergeContext (cardToValue card)
      (.object #[("csrfToken", .string ctx.csrfToken)])
    Loom.Stencil.ActionM.render "kanban/edit-card" data

-- Update card
action kanbanUpdateCard "/kanban/card/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  let description := ctx.paramD "description" ""
  let labels := ctx.paramD "labels" ""
  if title.isEmpty then return ← badRequest "Card title is required"
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    let db ← AuditTxM.getDb
    let (oldTitle, oldDesc, oldLabels) := match DbCard.pull db eid with
      | some c => (c.title, c.description, c.labels)
      | none => ("", "", "")
    DbCard.TxM.setTitle eid title
    DbCard.TxM.setDescription eid description
    DbCard.TxM.setLabels eid labels
    let changes :=
      (if oldTitle != title then [("old_title", oldTitle), ("new_title", title)] else []) ++
      (if oldDesc != description then [("description_changed", "true")] else []) ++
      (if oldLabels != labels then [("old_labels", oldLabels), ("new_labels", labels)] else [])
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
  let cardEid : EntityId := ⟨id⟩
  let colEid : EntityId := ⟨newColumnId⟩
  runAuditTx! do
    let db ← AuditTxM.getDb
    let oldColumnId := match DbCard.pull db cardEid with
      | some c => c.column.id.toNat
      | none => 0
    let cards := getCardsForColumn db colEid
    let order := match cards.map (·.order) with
      | [] => 0
      | orders => (orders.foldl max 0) + 1
    DbCard.TxM.setColumn cardEid colEid
    DbCard.TxM.setOrder cardEid order
    audit "MOVE" "card" id [("old_column_id", toString oldColumnId), ("new_column_id", toString newColumnId)]
  let ctx ← getCtx
  match getCard ctx id with
  | none => notFound "Card not found"
  | some (card, _) =>
    let _ ← SSE.publishEvent "kanban" "card-moved" (jsonStr! { "cardId" : id, newColumnId })
    Loom.Stencil.ActionM.renderPartial "kanban/_card" (cardToValue card)

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
