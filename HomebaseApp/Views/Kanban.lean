/-
  HomebaseApp.Views.Kanban - Kanban board view with columns and cards
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.Kanban

open Scribe
open Loom
open HomebaseApp.Views.Layout

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
       class_ "bg-white p-3 rounded-lg shadow-sm border border-slate-200 hover:shadow-md transition-shadow cursor-pointer group"] do
    -- Card header with actions
    div [class_ "flex justify-between items-start mb-2"] do
      h4 [class_ "font-medium text-slate-800 flex-1"] (text card.title)
      div [class_ "flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity"] do
        -- Edit button
        button [class_ "p-1 text-slate-400 hover:text-blue-600",
                hx_get s!"/kanban/card/{card.id}/edit",
                hx_target s!"#card-{card.id}",
                hx_swap "outerHTML"]
          (span [class_ "text-sm"] (text "✏️"))
        -- Delete button
        button [class_ "p-1 text-slate-400 hover:text-red-600",
                hx_delete s!"/kanban/card/{card.id}",
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

-- Render card edit form
def renderCardEditForm (ctx : Context) (card : Card) : HtmlM Unit := do
  div [id_ s!"card-{card.id}",
       class_ "bg-white p-3 rounded-lg shadow-sm border-2 border-blue-400"] do
    form [hx_put s!"/kanban/card/{card.id}",
          hx_target s!"#card-{card.id}",
          hx_swap "outerHTML"] do
      input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
      div [class_ "space-y-2"] do
        input [type_ "text", name_ "title", value_ card.title,
               class_ "w-full px-2 py-1 border border-slate-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
               placeholder_ "Card title", required_]
        textarea [name_ "description", rows_ 2,
                  class_ "w-full px-2 py-1 border border-slate-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
                  placeholder_ "Description (optional)"]
          card.description
        input [type_ "text", name_ "labels", value_ card.labels,
               class_ "w-full px-2 py-1 border border-slate-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
               placeholder_ "Labels (comma-separated)"]
        div [class_ "flex gap-2 justify-end"] do
          button [type_ "button",
                  class_ "px-2 py-1 text-sm text-slate-600 hover:text-slate-800",
                  hx_get s!"/kanban/card/{card.id}",
                  hx_target s!"#card-{card.id}",
                  hx_swap "outerHTML"]
            (text "Cancel")
          button [type_ "submit",
                  class_ "px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"]
            (text "Save")

-- Render add card form (inline)
def renderAddCardForm (ctx : Context) (columnId : Nat) : HtmlM Unit := do
  div [id_ s!"add-card-form-{columnId}",
       class_ "p-2 bg-slate-50 rounded-lg"] do
    form [hx_post "/kanban/card",
          hx_target s!"#column-cards-{columnId}",
          hx_swap "beforeend"] do
      input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
      input [type_ "hidden", name_ "column_id", value_ (toString columnId)]
      div [class_ "space-y-2"] do
        input [type_ "text", name_ "title",
               class_ "w-full px-2 py-1 border border-slate-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
               placeholder_ "Card title", required_, autofocus_]
        textarea [name_ "description", rows_ 2,
                  class_ "w-full px-2 py-1 border border-slate-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
                  placeholder_ "Description (optional)"]
        input [type_ "text", name_ "labels",
               class_ "w-full px-2 py-1 border border-slate-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
               placeholder_ "Labels (comma-separated)"]
        div [class_ "flex gap-2 justify-end"] do
          button [type_ "button",
                  class_ "px-2 py-1 text-sm text-slate-600 hover:text-slate-800",
                  hx_get s!"/kanban/column/{columnId}/add-card-button",
                  hx_target s!"#add-card-form-{columnId}",
                  hx_swap "outerHTML"]
            (text "Cancel")
          button [type_ "submit",
                  class_ "px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"]
            (text "Add Card")

-- Render add card button (shows form when clicked)
def renderAddCardButton (columnId : Nat) : HtmlM Unit := do
  div [id_ s!"add-card-form-{columnId}"] do
    button [class_ "w-full py-2 text-sm text-slate-500 hover:text-slate-700 hover:bg-slate-100 rounded transition-colors",
            hx_get s!"/kanban/column/{columnId}/add-card-form",
            hx_target s!"#add-card-form-{columnId}",
            hx_swap "outerHTML"]
      (text "+ Add card")

-- Render a single column
def renderColumn (ctx : Context) (col : Column) : HtmlM Unit := do
  div [id_ s!"column-{col.id}",
       class_ "flex-shrink-0 w-72 bg-slate-100 rounded-xl p-3 flex flex-col max-h-full"] do
    -- Column header
    div [class_ "flex justify-between items-center mb-3 group"] do
      h3 [class_ "font-semibold text-slate-700"] (text col.name)
      div [class_ "flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity"] do
        -- Edit column button
        button [class_ "p-1 text-slate-400 hover:text-blue-600",
                hx_get s!"/kanban/column/{col.id}/edit",
                hx_target s!"#column-{col.id}",
                hx_swap "outerHTML"]
          (span [class_ "text-xs"] (text "✏️"))
        -- Delete column button
        button [class_ "p-1 text-slate-400 hover:text-red-600",
                hx_delete s!"/kanban/column/{col.id}",
                hx_target s!"#column-{col.id}",
                hx_swap "outerHTML",
                hx_confirm s!"Delete column '{col.name}' and all its cards?"]
          (span [class_ "text-xs"] (text "🗑️"))
    -- Cards container
    div [id_ s!"column-cards-{col.id}",
         class_ "flex-1 space-y-2 overflow-y-auto min-h-[100px]"] do
      for card in col.cards do
        renderCard ctx card
    -- Add card button/form
    div [class_ "mt-3"] do
      renderAddCardButton col.id

-- Render column edit form
def renderColumnEditForm (ctx : Context) (col : Column) : HtmlM Unit := do
  div [id_ s!"column-{col.id}",
       class_ "flex-shrink-0 w-72 bg-slate-100 rounded-xl p-3"] do
    form [hx_put s!"/kanban/column/{col.id}",
          hx_target s!"#column-{col.id}",
          hx_swap "outerHTML"] do
      input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
      div [class_ "flex gap-2"] do
        input [type_ "text", name_ "name", value_ col.name,
               class_ "flex-1 px-2 py-1 border border-slate-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
               placeholder_ "Column name", required_, autofocus_]
        button [type_ "submit",
                class_ "px-2 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"]
          (text "Save")
        button [type_ "button",
                class_ "px-2 py-1 text-sm text-slate-600 hover:text-slate-800",
                hx_get s!"/kanban/column/{col.id}",
                hx_target s!"#column-{col.id}",
                hx_swap "outerHTML"]
          (text "Cancel")

-- Render add column form
def renderAddColumnForm (ctx : Context) : HtmlM Unit := do
  div [id_ "add-column-form",
       class_ "flex-shrink-0 w-72 bg-slate-50 rounded-xl p-3 border-2 border-dashed border-slate-300"] do
    form [hx_post "/kanban/column",
          hx_target "#add-column-form",
          hx_swap "outerHTML"] do
      input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
      div [class_ "space-y-2"] do
        input [type_ "text", name_ "name",
               class_ "w-full px-2 py-1 border border-slate-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500",
               placeholder_ "Column name", required_, autofocus_]
        div [class_ "flex gap-2 justify-end"] do
          button [type_ "button",
                  class_ "px-2 py-1 text-sm text-slate-600 hover:text-slate-800",
                  hx_get "/kanban/add-column-button",
                  hx_target "#add-column-form",
                  hx_swap "outerHTML"]
            (text "Cancel")
          button [type_ "submit",
                  class_ "px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"]
            (text "Add Column")

-- Render add column button
def renderAddColumnButton : HtmlM Unit := do
  div [id_ "add-column-form",
       class_ "flex-shrink-0 w-72"] do
    button [class_ "w-full py-8 text-slate-500 hover:text-slate-700 hover:bg-slate-100 rounded-xl border-2 border-dashed border-slate-300 transition-colors",
            hx_get "/kanban/add-column-form",
            hx_target "#add-column-form",
            hx_swap "outerHTML"]
      (text "+ Add column")

-- Move card dropdown (for moving cards between columns)
def renderMoveCardDropdown (ctx : Context) (card : Card) (columns : List Column) (currentColumnId : Nat) : HtmlM Unit := do
  div [class_ "relative group/move"] do
    button [class_ "p-1 text-slate-400 hover:text-green-600"]
      (span [class_ "text-sm"] (text "➡️"))
    div [class_ "hidden group-hover/move:block absolute right-0 top-6 bg-white border rounded shadow-lg z-10 min-w-[120px]"] do
      for col in columns do
        if col.id != currentColumnId then
          button [class_ "w-full px-3 py-1 text-left text-sm hover:bg-slate-100",
                  hx_post s!"/kanban/card/{card.id}/move",
                  hx_vals s!"\{\"column_id\": {col.id}}",
                  hx_target s!"#card-{card.id}",
                  hx_swap "outerHTML swap:1s"]
            (text col.name)

-- Main board content
def boardContent (ctx : Context) (columns : List Column) : HtmlM Unit := do
  -- HTMX script
  script [src_ "https://unpkg.com/htmx.org@2.0.4"]

  div [class_ "h-full flex flex-col"] do
    -- Header
    div [class_ "flex justify-between items-center mb-6"] do
      h1 [class_ "text-2xl font-bold text-slate-800"] (text "Kanban Board")
      div [class_ "flex gap-2"] do
        span [class_ "text-sm text-slate-500"]
          (text s!"{columns.length} columns")

    -- Board container with horizontal scroll
    div [class_ "flex-1 overflow-x-auto pb-4"] do
      div [id_ "board-columns",
           class_ "flex gap-4 h-full items-start"] do
        -- Render existing columns
        for col in columns do
          renderColumn ctx col
        -- Add column button
        renderAddColumnButton

-- Full page render
def render (ctx : Context) (columns : List Column) : String :=
  Layout.render ctx "Kanban - Homebase" "/kanban" (boardContent ctx columns)

-- Partial renders for HTMX responses
def renderCardPartial (ctx : Context) (card : Card) : String :=
  HtmlM.render (renderCard ctx card)

def renderCardEditFormPartial (ctx : Context) (card : Card) : String :=
  HtmlM.render (renderCardEditForm ctx card)

def renderColumnPartial (ctx : Context) (col : Column) : String :=
  HtmlM.render (renderColumn ctx col)

def renderColumnEditFormPartial (ctx : Context) (col : Column) : String :=
  HtmlM.render (renderColumnEditForm ctx col)

def renderAddCardFormPartial (ctx : Context) (columnId : Nat) : String :=
  HtmlM.render (renderAddCardForm ctx columnId)

def renderAddCardButtonPartial (columnId : Nat) : String :=
  HtmlM.render (renderAddCardButton columnId)

def renderAddColumnFormPartial (ctx : Context) : String :=
  HtmlM.render (renderAddColumnForm ctx)

def renderAddColumnButtonPartial : String :=
  HtmlM.render renderAddColumnButton

end HomebaseApp.Views.Kanban
