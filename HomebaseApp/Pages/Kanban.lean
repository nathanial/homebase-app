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

def renderColumn (ctx : Context) (col : Column) : HtmlM Unit := do
  div [id_ s!"column-{col.id}", class_ "kanban-column"] do
    div [class_ "kanban-column-header"] do
      h3 [class_ "kanban-column-title"] (text col.name)
      div [class_ "kanban-column-actions"] do
        -- Add card button (opens modal)
        button [hx_get s!"/kanban/column/{col.id}/add-card-form",
                hx_target "#modal-container", hx_swap "innerHTML",
                class_ "btn-icon", title_ "Add card"] (text "+")
        -- Edit column button (opens modal)
        button [hx_get s!"/kanban/column/{col.id}/edit",
                hx_target "#modal-container", hx_swap "innerHTML",
                class_ "btn-icon", title_ "Edit column"] (text "e")
        -- Delete column button (SSE refreshes board)
        button [hx_delete s!"/kanban/column/{col.id}",
                hx_swap "none", hx_confirm s!"Delete column '{col.name}' and all its cards?",
                class_ "btn-icon btn-icon-danger", title_ "Delete column"] (text "x")
    div [id_ s!"column-cards-{col.id}", data_ "column-id" (toString col.id),
         class_ "kanban-column-cards sortable-cards"] do
      for card in col.cards do renderCard ctx card

/-- Render a single board item in the sidebar -/
def renderBoardItem (board : Board) (isActive : Bool) : HtmlM Unit := do
  let activeClass := if isActive then " active" else ""
  a [href_ s!"/kanban/board/{board.id}", class_ s!"kanban-sidebar-item{activeClass}"] do
    span [class_ "kanban-sidebar-item-name"] (text board.name)
    if isActive then
      div [class_ "kanban-sidebar-item-actions"] do
        button [hx_get s!"/kanban/board/{board.id}/edit",
                hx_target "#modal-container", hx_swap "innerHTML",
                class_ "btn-icon", title_ "Edit board",
                attr_ "onclick" "event.preventDefault(); event.stopPropagation();"] (text "e")
        button [hx_delete s!"/kanban/board/{board.id}",
                hx_swap "none", hx_confirm s!"Delete board '{board.name}' and all its columns/cards?",
                class_ "btn-icon btn-icon-danger", title_ "Delete board",
                attr_ "onclick" "event.preventDefault(); event.stopPropagation();"] (text "x")

/-- Render the board sidebar -/
def renderBoardSidebar (boards : List Board) (activeBoard : Option Board) : HtmlM Unit := do
  aside [class_ "kanban-sidebar"] do
    div [class_ "kanban-sidebar-header"] do
      span [class_ "kanban-sidebar-title"] (text "Boards")
      button [hx_get "/kanban/add-board-form",
              hx_target "#modal-container", hx_swap "innerHTML",
              class_ "btn-icon text-muted", title_ "Add board"] (text "+")
    div [class_ "kanban-sidebar-list"] do
      for board in boards do
        renderBoardItem board (activeBoard.map (·.id) == some board.id)

/-- Render the full kanban page content with sidebar and board -/
def kanbanPageContent (ctx : Context) (boards : List Board) (activeBoard : Board) (columns : List Column) : HtmlM Unit := do
  div [class_ "kanban-wrapper"] do
    renderBoardSidebar boards (some activeBoard)
    div [id_ "kanban-board", class_ "kanban-board"] do
      div [class_ "kanban-header"] do
        h1 [class_ "kanban-title"] (text activeBoard.name)
        button [hx_get s!"/kanban/board/{activeBoard.id}/add-column-form",
                hx_target "#modal-container", hx_swap "innerHTML",
                class_ "btn-icon text-muted", title_ "Add column"] (text "+")
        div [class_ "kanban-meta"] do
          span [id_ "sse-status", class_ "status-indicator"] (text "* Live")
          span [class_ "kanban-count"] (text s!"{columns.length} columns")
      div [class_ "kanban-scroll"] do
        div [id_ "board-columns", class_ "kanban-columns"] do
          for col in columns do renderColumn ctx col
  div [id_ "modal-container"] (pure ())
  script [src_ "/js/kanban.js"]

/-- Legacy boardContent for backward compatibility -/
def boardContent (ctx : Context) (columns : List Column) : HtmlM Unit := do
  div [id_ "kanban-board", class_ "kanban-board"] do
    div [class_ "kanban-header"] do
      h1 [class_ "kanban-title"] (text "Kanban Board")
      button [hx_get "/kanban/add-column-form",
              hx_target "#modal-container", hx_swap "innerHTML",
              class_ "btn-icon text-muted", title_ "Add column"] (text "+")
      div [class_ "kanban-meta"] do
        span [id_ "sse-status", class_ "status-indicator"] (text "* Live")
        span [class_ "kanban-count"] (text s!"{columns.length} columns")
    div [class_ "kanban-scroll"] do
      div [id_ "board-columns", class_ "kanban-columns"] do
        for col in columns do renderColumn ctx col
  div [id_ "modal-container"] (pure ())
  script [src_ "/js/kanban.js"]

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
    html (Shared.render ctx s!"{board.name} - Kanban - Homebase" "/kanban" (kanbanPageContent ctx boards board columns))

-- Get all columns for a board (for SSE refresh)
view kanbanBoardColumns "/kanban/board/:boardId/columns" [HomebaseApp.Middleware.authRequired] (boardId : Nat) do
  let ctx ← getCtx
  let columns := getColumnsWithCardsForBoard ctx boardId
  html (HtmlM.render do
    for col in columns do renderColumn ctx col)

-- Note: SSE endpoint "/events/kanban" is registered separately in Main.lean

-- Add board form
view kanbanAddBoardForm "/kanban/add-board-form" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  html (HtmlM.render do
    div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
      div [class_ "modal-container modal-sm"] do
        h3 [class_ "modal-title"] (text "Add Board")
        form [hx_post "/kanban/board", hx_swap "none", modalClearAttr] do
          csrfField ctx.csrfToken
          div [class_ "form-stack"] do
            div [class_ "form-group"] do
              label [for_ "name", class_ "form-label"] (text "Board Name")
              input [type_ "text", name_ "name", id_ "name", class_ "form-input",
                     placeholder_ "Board name", required_, autofocus_]
            div [class_ "form-actions"] do
              button [type_ "button", class_ "btn btn-secondary",
                      attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
              button [type_ "submit", class_ "btn btn-primary"] (text "Add Board"))

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
    html (HtmlM.render do
      div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
        div [class_ "modal-container modal-sm"] do
          h3 [class_ "modal-title"] (text "Edit Board")
          form [hx_put s!"/kanban/board/{board.id}", hx_swap "none", modalClearAttr] do
            csrfField ctx.csrfToken
            div [class_ "form-stack"] do
              div [class_ "form-group"] do
                label [for_ "name", class_ "form-label"] (text "Board Name")
                input [type_ "text", name_ "name", id_ "name", value_ board.name,
                       class_ "form-input", placeholder_ "Board name", required_, autofocus_]
              div [class_ "form-actions"] do
                button [type_ "button", class_ "btn btn-secondary",
                        attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"] (text "Cancel")
                button [type_ "submit", class_ "btn btn-primary"] (text "Save"))

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
  html (HtmlM.render do
    div [class_ "modal-overlay", attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
      div [class_ "modal-container modal-sm"] do
        h3 [class_ "modal-title"] (text "Add Column")
        form [hx_post s!"/kanban/board/{boardId}/column", hx_swap "none", modalClearAttr] do
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
