/-
  HomebaseApp.Views.Kanban - Kanban board view with columns and cards
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout
import HomebaseApp.Routes

namespace HomebaseApp.Views.Kanban

open Scribe
open Loom
open Loom.Json
open HomebaseApp.Views.Layout
open HomebaseApp (Route)

-- Data structures for view rendering
structure Card where
  id : Nat
  title : String
  description : String
  labels : String  -- comma-separated labels
  order : Nat
  deriving Inhabited

structure Column where
  id : Nat
  name : String
  order : Nat
  cards : List Card
  deriving Inhabited

-- Label colors mapping
def labelColor (label : String) : String :=
  match label.trim.toLower with
  | "bug" => "bg-red-100 text-red-800"
  | "feature" => "bg-blue-100 text-blue-800"
  | "urgent" => "bg-orange-100 text-orange-800"
  | "low" => "bg-gray-100 text-gray-800"
  | "high" => "bg-yellow-100 text-yellow-800"
  | "blocked" => "bg-purple-100 text-purple-800"
  | _ => "bg-slate-100 text-slate-800"

-- Render a single label
def renderLabel (label : String) : HtmlM Unit := do
  if label.trim.isEmpty then pure ()
  else
    span [class_ s!"px-2 py-0.5 text-xs rounded-full {labelColor label}"]
      (text label.trim)

-- Render labels for a card
def renderLabels (labelsStr : String) : HtmlM Unit := do
  let labels := labelsStr.splitOn ","
  div [class_ "flex flex-wrap gap-1 mb-2"] do
    for label in labels do
      renderLabel label

-- Render a single card
def renderCard (ctx : Context) (card : Card) : HtmlM Unit := do
  div [id_ s!"card-{card.id}",
       data_ "card-id" (toString card.id),
       class_ "bg-white p-3 rounded-lg shadow-sm border border-slate-200 hover:shadow-md transition-shadow cursor-grab active:cursor-grabbing group"] do
    -- Card header with actions
    div [class_ "flex justify-between items-start mb-2"] do
      h4 [class_ "font-medium text-slate-800 flex-1"] (text card.title)
      div [class_ "flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity"] do
        -- Edit button - opens modal (typed route)
        button [class_ "p-1 text-slate-400 hover:text-blue-600",
                hx_get' (Route.kanbanEditCardForm card.id),
                hx_target "#modal-container",
                hx_swap "innerHTML"]
          (span [class_ "text-sm"] (text "✏️"))
        -- Delete button (typed route)
        button [class_ "p-1 text-slate-400 hover:text-red-600",
                hx_delete' (Route.kanbanDeleteCard card.id),
                hx_target s!"#card-{card.id}",
                hx_swap "outerHTML",
                hx_confirm "Delete this card?"]
          (span [class_ "text-sm"] (text "🗑️"))
    -- Labels
    if !card.labels.isEmpty then
      renderLabels card.labels
    -- Description preview
    if !card.description.isEmpty then
      p [class_ "text-sm text-slate-500 line-clamp-2"] (text card.description)

-- Render card edit form as modal
def renderCardEditForm (ctx : Context) (card : Card) : HtmlM Unit := do
  div [class_ "fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "bg-white rounded-lg shadow-xl p-4 w-96"] do
      h3 [class_ "font-semibold text-slate-700 mb-3"] (text "Edit Card")
      form [hx_put' (Route.kanbanUpdateCard card.id),
            hx_target s!"#card-{card.id}",
            hx_swap "outerHTML",
            attr_ "hx-on::after-request" "document.getElementById('modal-container').innerHTML = ''"] do
        input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
        div [class_ "space-y-3"] do
          div [] do
            label [for_ "title", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Title")
            input [type_ "text", name_ "title", id_ "title", value_ card.title,
                   class_ "w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
                   placeholder_ "Card title", required_, autofocus_]
          div [] do
            label [for_ "description", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Description")
            textarea [name_ "description", id_ "description", rows_ 3,
                      class_ "w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
                      placeholder_ "Description (optional)"]
              card.description
          div [] do
            label [for_ "labels", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Labels")
            input [type_ "text", name_ "labels", id_ "labels", value_ card.labels,
                   class_ "w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
                   placeholder_ "bug, feature, urgent (comma-separated)"]
          div [class_ "flex gap-2 justify-end pt-2"] do
            button [type_ "button",
                    class_ "px-3 py-2 text-sm text-slate-600 hover:text-slate-800",
                    attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"]
              (text "Cancel")
            button [type_ "submit",
                    class_ "px-4 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700"]
              (text "Save Changes")

-- Render add card form as modal
def renderAddCardForm (ctx : Context) (columnId : Nat) : HtmlM Unit := do
  div [class_ "fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "bg-white rounded-lg shadow-xl p-4 w-96"] do
      h3 [class_ "font-semibold text-slate-700 mb-3"] (text "Add Card")
      form [hx_post' Route.kanbanCreateCard,
            hx_target_vol (volatileTarget s!"column-cards-{columnId}"),
            hx_swap "beforeend",
            attr_ "hx-on::after-request" "document.getElementById('modal-container').innerHTML = ''"] do
        input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
        input [type_ "hidden", name_ "column_id", value_ (toString columnId)]
        div [class_ "space-y-3"] do
          div [] do
            label [for_ "title", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Title")
            input [type_ "text", name_ "title", id_ "title",
                   class_ "w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
                   placeholder_ "Card title", required_, autofocus_]
          div [] do
            label [for_ "description", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Description")
            textarea [name_ "description", id_ "description", rows_ 2,
                      class_ "w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
                      placeholder_ "Description (optional)"]
          div [] do
            label [for_ "labels", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Labels")
            input [type_ "text", name_ "labels", id_ "labels",
                   class_ "w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
                   placeholder_ "bug, feature, urgent (comma-separated)"]
          div [class_ "flex gap-2 justify-end pt-2"] do
            button [type_ "button",
                    class_ "px-3 py-2 text-sm text-slate-600 hover:text-slate-800",
                    attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"]
              (text "Cancel")
            button [type_ "submit",
                    class_ "px-4 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700"]
              (text "Add Card")

-- Render add card button
def renderAddCardButton (columnId : Nat) : HtmlM Unit := do
  button [class_ "w-full py-2 text-sm text-slate-500 hover:text-slate-700 hover:bg-slate-100 rounded transition-colors",
          hx_get' (Route.kanbanAddCardForm columnId),
          hx_target "#modal-container",
          hx_swap "innerHTML"]
    (text "+ Add card")

-- Render a single column
def renderColumn (ctx : Context) (col : Column) : HtmlM Unit := do
  div [id_ s!"column-{col.id}",
       class_ "flex-shrink-0 w-72 bg-slate-100 rounded-xl p-3 flex flex-col max-h-full"] do
    -- Column header
    div [class_ "flex justify-between items-center mb-3 group"] do
      h3 [class_ "font-semibold text-slate-700"] (text col.name)
      div [class_ "flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity"] do
        -- Edit column button - opens modal (typed route)
        button [class_ "p-1 text-slate-400 hover:text-blue-600",
                hx_get' (Route.kanbanEditColumnForm col.id),
                hx_target "#modal-container",
                hx_swap "innerHTML"]
          (span [class_ "text-xs"] (text "✏️"))
        -- Delete column button (typed route)
        button [class_ "p-1 text-slate-400 hover:text-red-600",
                hx_delete' (Route.kanbanDeleteColumn col.id),
                hx_target s!"#column-{col.id}",
                hx_swap "outerHTML",
                hx_confirm s!"Delete column '{col.name}' and all its cards?"]
          (span [class_ "text-xs"] (text "🗑️"))
    -- Cards container (sortable drop zone)
    div [id_ s!"column-cards-{col.id}",
         data_ "column-id" (toString col.id),
         class_ "flex-1 space-y-2 overflow-y-auto min-h-[100px] sortable-cards"] do
      for card in col.cards do
        renderCard ctx card
    -- Add card button/form
    div [class_ "mt-3"] do
      renderAddCardButton col.id

-- Render column edit form as modal
def renderColumnEditForm (ctx : Context) (col : Column) : HtmlM Unit := do
  div [class_ "fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "bg-white rounded-lg shadow-xl p-4 w-80"] do
      h3 [class_ "font-semibold text-slate-700 mb-3"] (text "Edit Column")
      form [hx_put' (Route.kanbanUpdateColumn col.id),
            hx_target s!"#column-{col.id}",
            hx_swap "outerHTML",
            attr_ "hx-on::after-request" "document.getElementById('modal-container').innerHTML = ''"] do
        input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
        div [class_ "space-y-3"] do
          div [] do
            label [for_ "name", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Column Name")
            input [type_ "text", name_ "name", id_ "name", value_ col.name,
                   class_ "w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
                   placeholder_ "Column name", required_, autofocus_]
          div [class_ "flex gap-2 justify-end pt-2"] do
            button [type_ "button",
                    class_ "px-3 py-2 text-sm text-slate-600 hover:text-slate-800",
                    attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"]
              (text "Cancel")
            button [type_ "submit",
                    class_ "px-4 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700"]
              (text "Save")

-- Render add column form as modal
def renderAddColumnForm (ctx : Context) : HtmlM Unit := do
  div [class_ "fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "bg-white rounded-lg shadow-xl p-4 w-80"] do
      h3 [class_ "font-semibold text-slate-700 mb-3"] (text "Add Column")
      form [hx_post' Route.kanbanCreateColumn,
            hx_target_vol (volatileTarget "board-columns"),
            hx_swap "beforeend",
            attr_ "hx-on::after-request" "document.getElementById('modal-container').innerHTML = ''"] do
        input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
        div [class_ "space-y-3"] do
          div [] do
            label [for_ "name", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Column Name")
            input [type_ "text", name_ "name", id_ "name",
                   class_ "w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
                   placeholder_ "Column name", required_, autofocus_]
          div [class_ "flex gap-2 justify-end pt-2"] do
            button [type_ "button",
                    class_ "px-3 py-2 text-sm text-slate-600 hover:text-slate-800",
                    attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"]
              (text "Cancel")
            button [type_ "submit",
                    class_ "px-4 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700"]
              (text "Add Column")

-- Render add column button
def renderAddColumnButton : HtmlM Unit := do
  div [class_ "flex-shrink-0 w-72"] do
    button [class_ "w-full py-8 text-slate-500 hover:text-slate-700 hover:bg-slate-100 rounded-xl border-2 border-dashed border-slate-300 transition-colors",
            hx_get' Route.kanbanAddColumnForm,
            hx_target "#modal-container",
            hx_swap "innerHTML"]
      (text "+ Add column")

-- Move card dropdown
def renderMoveCardDropdown (ctx : Context) (card : Card) (columns : List Column) (currentColumnId : Nat) : HtmlM Unit := do
  div [class_ "relative group/move"] do
    button [class_ "p-1 text-slate-400 hover:text-green-600"]
      (span [class_ "text-sm"] (text "➡️"))
    div [class_ "hidden group-hover/move:block absolute right-0 top-6 bg-white border rounded shadow-lg z-10 min-w-[120px]"] do
      for col in columns do
        if col.id != currentColumnId then
          button [class_ "w-full px-3 py-1 text-left text-sm hover:bg-slate-100",
                  hx_post' (Route.kanbanMoveCard card.id),
                  hx_vals (jsonStr! { "column_id" : col.id }),
                  hx_target s!"#card-{card.id}",
                  hx_swap "outerHTML swap:1s"]
            (text col.name)

-- Main board content
def boardContent (ctx : Context) (columns : List Column) : HtmlM Unit := do
  -- HTMX script
  script [src_ "https://unpkg.com/htmx.org@2.0.4"]
  -- SortableJS for drag and drop
  script [src_ "https://cdn.jsdelivr.net/npm/sortablejs@1.15.2/Sortable.min.js"]

  -- Kanban board container
  div [id_ "kanban-board"] do
    div [class_ "h-full flex flex-col"] do
      -- Header
      div [class_ "flex justify-between items-center mb-6"] do
        h1 [class_ "text-2xl font-bold text-slate-800"] (text "Kanban Board")
        div [class_ "flex gap-2"] do
          -- SSE connection indicator
          span [id_ "sse-status", class_ "text-xs text-green-500"] (text "● Live")
          span [class_ "text-sm text-slate-500"]
            (text s!"{columns.length} columns")

      -- Board container with horizontal scroll
      div [class_ "flex-1 overflow-x-auto pb-4"] do
        div [id_ "board-columns", class_ "flex gap-4 h-full items-start"] do
          -- Render existing columns
          for col in columns do
            renderColumn ctx col
          -- Add column button
          renderAddColumnButton

  -- Modal container
  div [id_ "modal-container"] do
    pure ()

  -- Kanban JavaScript (drag-and-drop + SSE)
  script [src' (Route.staticJs "kanban.js")]

  -- Custom styles for sortable
  style [] "
    .sortable-ghost { opacity: 0.5; }
    .sortable-drag { box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1); }
    .sortable-chosen { outline: 2px solid #3b82f6; outline-offset: 2px; }
  "

-- Full page render
def render (ctx : Context) (columns : List Column) : String :=
  Layout.render ctx "Kanban - Homebase" "/kanban" (boardContent ctx columns)

-- Partial renders for HTMX responses

-- Card partials
def renderCardPartial (ctx : Context) (card : Card) : String :=
  HtmlM.render (renderCard ctx card)

-- Card edit form
def renderCardEditFormPartial (ctx : Context) (card : Card) : String :=
  HtmlM.render (renderCardEditForm ctx card)

-- Column partial
def renderColumnPartial (ctx : Context) (col : Column) : String :=
  HtmlM.render (renderColumn ctx col)

-- Column edit form
def renderColumnEditFormPartial (ctx : Context) (col : Column) : String :=
  HtmlM.render (renderColumnEditForm ctx col)

-- Add card form
def renderAddCardFormPartial (ctx : Context) (columnId : Nat) : String :=
  HtmlM.render (renderAddCardForm ctx columnId)

-- Add card button
def renderAddCardButtonPartial (columnId : Nat) : String :=
  HtmlM.render (renderAddCardButton columnId)

-- Add column form
def renderAddColumnFormPartial (ctx : Context) : String :=
  HtmlM.render (renderAddColumnForm ctx)

-- Render all columns (for SSE refresh)
def renderColumnsPartial (ctx : Context) (columns : List Column) : String :=
  HtmlM.render do
    for col in columns do
      renderColumn ctx col
    renderAddColumnButton

-- Add column button
def renderAddColumnButtonPartial : String :=
  HtmlM.render renderAddColumnButton

end HomebaseApp.Views.Kanban
