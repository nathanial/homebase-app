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

-- Label class mapping
def labelClass (label : String) : String :=
  match label.trim.toLower with
  | "bug" => "label-bug"
  | "feature" => "label-feature"
  | "urgent" => "label-urgent"
  | "low" => "label-low"
  | "high" => "label-high"
  | "blocked" => "label-blocked"
  | _ => "label-default"

-- Render a single label
def renderLabel (label : String) : HtmlM Unit := do
  if label.trim.isEmpty then pure ()
  else
    span [class_ s!"label {labelClass label}"] (text label.trim)

-- Render labels for a card
def renderLabels (labelsStr : String) : HtmlM Unit := do
  let labels := labelsStr.splitOn ","
  div [class_ "kanban-labels"] do
    for label in labels do
      renderLabel label

-- Render a single card
def renderCard (ctx : Context) (card : Card) : HtmlM Unit := do
  div [id_ s!"card-{card.id}",
       data_ "card-id" (toString card.id),
       class_ "kanban-card"] do
    -- Card header with actions
    div [class_ "kanban-card-header"] do
      h4 [class_ "kanban-card-title"] (text card.title)
      div [class_ "kanban-card-actions"] do
        -- Edit button - opens modal (typed route)
        button [class_ "btn-icon",
                hx_get' (Route.kanbanEditCardForm card.id),
                hx_target "#modal-container",
                hx_swap "innerHTML"]
          (text "✏️")
        -- Delete button (typed route)
        button [class_ "btn-icon btn-icon-danger",
                hx_delete' (Route.kanbanDeleteCard card.id),
                hx_target s!"#card-{card.id}",
                hx_swap "outerHTML",
                hx_confirm "Delete this card?"]
          (text "🗑️")
    -- Labels
    if !card.labels.isEmpty then
      renderLabels card.labels
    -- Description preview
    if !card.description.isEmpty then
      p [class_ "kanban-card-description"] (text card.description)

-- Render card edit form as modal
def renderCardEditForm (ctx : Context) (card : Card) : HtmlM Unit := do
  div [class_ "modal-overlay",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "modal-container modal-md"] do
      h3 [class_ "modal-title"] (text "Edit Card")
      form [hx_put' (Route.kanbanUpdateCard card.id),
            hx_target s!"#card-{card.id}",
            hx_swap "outerHTML",
            attr_ "hx-on::after-request" "document.getElementById('modal-container').innerHTML = ''"] do
        input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
        div [class_ "form-stack"] do
          div [class_ "form-group"] do
            label [for_ "title", class_ "form-label"] (text "Title")
            input [type_ "text", name_ "title", id_ "title", value_ card.title,
                   class_ "form-input", placeholder_ "Card title", required_, autofocus_]
          div [class_ "form-group"] do
            label [for_ "description", class_ "form-label"] (text "Description")
            textarea [name_ "description", id_ "description", rows_ 3,
                      class_ "form-textarea", placeholder_ "Description (optional)"]
              card.description
          div [class_ "form-group"] do
            label [for_ "labels", class_ "form-label"] (text "Labels")
            input [type_ "text", name_ "labels", id_ "labels", value_ card.labels,
                   class_ "form-input", placeholder_ "bug, feature, urgent (comma-separated)"]
          div [class_ "form-actions"] do
            button [type_ "button", class_ "btn btn-secondary",
                    attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"]
              (text "Cancel")
            button [type_ "submit", class_ "btn btn-primary"]
              (text "Save Changes")

-- Render add card form as modal
def renderAddCardForm (ctx : Context) (columnId : Nat) : HtmlM Unit := do
  div [class_ "modal-overlay",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "modal-container modal-md"] do
      h3 [class_ "modal-title"] (text "Add Card")
      form [hx_post' Route.kanbanCreateCard,
            hx_target_vol (volatileTarget s!"column-cards-{columnId}"),
            hx_swap "beforeend",
            attr_ "hx-on::after-request" "document.getElementById('modal-container').innerHTML = ''"] do
        input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
        input [type_ "hidden", name_ "column_id", value_ (toString columnId)]
        div [class_ "form-stack"] do
          div [class_ "form-group"] do
            label [for_ "title", class_ "form-label"] (text "Title")
            input [type_ "text", name_ "title", id_ "title",
                   class_ "form-input", placeholder_ "Card title", required_, autofocus_]
          div [class_ "form-group"] do
            label [for_ "description", class_ "form-label"] (text "Description")
            textarea [name_ "description", id_ "description", rows_ 2,
                      class_ "form-textarea", placeholder_ "Description (optional)"]
          div [class_ "form-group"] do
            label [for_ "labels", class_ "form-label"] (text "Labels")
            input [type_ "text", name_ "labels", id_ "labels",
                   class_ "form-input", placeholder_ "bug, feature, urgent (comma-separated)"]
          div [class_ "form-actions"] do
            button [type_ "button", class_ "btn btn-secondary",
                    attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"]
              (text "Cancel")
            button [type_ "submit", class_ "btn btn-primary"]
              (text "Add Card")

-- Render add card button
def renderAddCardButton (columnId : Nat) : HtmlM Unit := do
  button [class_ "kanban-add-card",
          hx_get' (Route.kanbanAddCardForm columnId),
          hx_target "#modal-container",
          hx_swap "innerHTML"]
    (text "+ Add card")

-- Render a single column
def renderColumn (ctx : Context) (col : Column) : HtmlM Unit := do
  div [id_ s!"column-{col.id}", class_ "kanban-column"] do
    -- Column header
    div [class_ "kanban-column-header"] do
      h3 [class_ "kanban-column-title"] (text col.name)
      div [class_ "kanban-column-actions"] do
        -- Edit column button - opens modal (typed route)
        button [class_ "btn-icon",
                hx_get' (Route.kanbanEditColumnForm col.id),
                hx_target "#modal-container",
                hx_swap "innerHTML"]
          (text "✏️")
        -- Delete column button (typed route)
        button [class_ "btn-icon btn-icon-danger",
                hx_delete' (Route.kanbanDeleteColumn col.id),
                hx_target s!"#column-{col.id}",
                hx_swap "outerHTML",
                hx_confirm s!"Delete column '{col.name}' and all its cards?"]
          (text "🗑️")
    -- Cards container (sortable drop zone)
    div [id_ s!"column-cards-{col.id}",
         data_ "column-id" (toString col.id),
         class_ "kanban-column-cards sortable-cards"] do
      for card in col.cards do
        renderCard ctx card
    -- Add card button/form
    renderAddCardButton col.id

-- Render column edit form as modal
def renderColumnEditForm (ctx : Context) (col : Column) : HtmlM Unit := do
  div [class_ "modal-overlay",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "modal-container modal-sm"] do
      h3 [class_ "modal-title"] (text "Edit Column")
      form [hx_put' (Route.kanbanUpdateColumn col.id),
            hx_target s!"#column-{col.id}",
            hx_swap "outerHTML",
            attr_ "hx-on::after-request" "document.getElementById('modal-container').innerHTML = ''"] do
        input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
        div [class_ "form-stack"] do
          div [class_ "form-group"] do
            label [for_ "name", class_ "form-label"] (text "Column Name")
            input [type_ "text", name_ "name", id_ "name", value_ col.name,
                   class_ "form-input", placeholder_ "Column name", required_, autofocus_]
          div [class_ "form-actions"] do
            button [type_ "button", class_ "btn btn-secondary",
                    attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"]
              (text "Cancel")
            button [type_ "submit", class_ "btn btn-primary"]
              (text "Save")

-- Render add column form as modal
def renderAddColumnForm (ctx : Context) : HtmlM Unit := do
  div [class_ "modal-overlay",
       attr_ "onclick" "if(event.target === this) this.parentElement.innerHTML = ''"] do
    div [class_ "modal-container modal-sm"] do
      h3 [class_ "modal-title"] (text "Add Column")
      form [hx_post' Route.kanbanCreateColumn,
            hx_target_vol (volatileTarget "board-columns"),
            hx_swap "beforeend",
            attr_ "hx-on::after-request" "document.getElementById('modal-container').innerHTML = ''"] do
        input [type_ "hidden", name_ "_csrf", value_ ctx.csrfToken]
        div [class_ "form-stack"] do
          div [class_ "form-group"] do
            label [for_ "name", class_ "form-label"] (text "Column Name")
            input [type_ "text", name_ "name", id_ "name",
                   class_ "form-input", placeholder_ "Column name", required_, autofocus_]
          div [class_ "form-actions"] do
            button [type_ "button", class_ "btn btn-secondary",
                    attr_ "onclick" "document.getElementById('modal-container').innerHTML = ''"]
              (text "Cancel")
            button [type_ "submit", class_ "btn btn-primary"]
              (text "Add Column")

-- Render add column button
def renderAddColumnButton : HtmlM Unit := do
  div [class_ "kanban-add-column-wrapper"] do
    button [class_ "kanban-add-column",
            hx_get' Route.kanbanAddColumnForm,
            hx_target "#modal-container",
            hx_swap "innerHTML"]
      (text "+ Add column")

-- Move card dropdown (currently unused but kept for future use)
def renderMoveCardDropdown (ctx : Context) (card : Card) (columns : List Column) (currentColumnId : Nat) : HtmlM Unit := do
  div [class_ "move-dropdown"] do
    button [class_ "btn-icon"] (text "➡️")
    div [class_ "move-dropdown-menu"] do
      for col in columns do
        if col.id != currentColumnId then
          button [class_ "move-dropdown-item",
                  hx_post' (Route.kanbanMoveCard card.id),
                  hx_vals (jsonStr! { "column_id" : col.id }),
                  hx_target s!"#card-{card.id}",
                  hx_swap "outerHTML swap:1s"]
            (text col.name)

-- Main board content
def boardContent (ctx : Context) (columns : List Column) : HtmlM Unit := do
  -- Kanban board container
  div [id_ "kanban-board", class_ "kanban-board"] do
    -- Header
    div [class_ "kanban-header"] do
      h1 [class_ "kanban-title"] (text "Kanban Board")
      div [class_ "kanban-meta"] do
        -- SSE connection indicator
        span [id_ "sse-status", class_ "status-indicator"] (text "● Live")
        span [class_ "kanban-count"] (text s!"{columns.length} columns")

    -- Board container with horizontal scroll
    div [class_ "kanban-scroll"] do
      div [id_ "board-columns", class_ "kanban-columns"] do
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
