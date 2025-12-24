/-
  HomebaseApp.Routes - Type-safe route definitions

  All routes are defined as a closed type, ensuring:
  - HTMX hx-get/hx-post attributes can only reference valid routes
  - Router and views share the same route definitions
  - Typos in route paths become compile errors
-/
import Scribe

namespace HomebaseApp

/-- Type-safe route definitions for the application -/
inductive Route where
  -- Main pages
  | home
  | login
  | register
  | logout
  -- Section pages
  | chat
  | notebook
  | time
  | health
  | recipes
  | gallery
  | news
  -- Kanban pages
  | kanban
  | kanbanColumns
  | kanbanEvents  -- SSE endpoint
  -- Kanban column routes
  | kanbanAddColumnForm
  | kanbanAddColumnButton
  | kanbanCreateColumn
  | kanbanGetColumn (id : Nat)
  | kanbanEditColumnForm (id : Nat)
  | kanbanUpdateColumn (id : Nat)
  | kanbanDeleteColumn (id : Nat)
  | kanbanAddCardForm (columnId : Nat)
  | kanbanAddCardButton (columnId : Nat)
  -- Kanban card routes
  | kanbanCreateCard
  | kanbanGetCard (id : Nat)
  | kanbanEditCardForm (id : Nat)
  | kanbanUpdateCard (id : Nat)
  | kanbanDeleteCard (id : Nat)
  | kanbanMoveCard (id : Nat)
  | kanbanReorderCard (id : Nat)
  -- Static files
  | staticJs (name : String)
  deriving Repr

namespace Route

/-- Convert a route to its URL path -/
def path : Route → String
  | .home => "/"
  | .login => "/login"
  | .register => "/register"
  | .logout => "/logout"
  | .chat => "/chat"
  | .notebook => "/notebook"
  | .time => "/time"
  | .health => "/health"
  | .recipes => "/recipes"
  | .gallery => "/gallery"
  | .news => "/news"
  | .kanban => "/kanban"
  | .kanbanColumns => "/kanban/columns"
  | .kanbanEvents => "/events/kanban"
  | .kanbanAddColumnForm => "/kanban/add-column-form"
  | .kanbanAddColumnButton => "/kanban/add-column-button"
  | .kanbanCreateColumn => "/kanban/column"
  | .kanbanGetColumn id => s!"/kanban/column/{id}"
  | .kanbanEditColumnForm id => s!"/kanban/column/{id}/edit"
  | .kanbanUpdateColumn id => s!"/kanban/column/{id}"
  | .kanbanDeleteColumn id => s!"/kanban/column/{id}"
  | .kanbanAddCardForm columnId => s!"/kanban/column/{columnId}/add-card-form"
  | .kanbanAddCardButton columnId => s!"/kanban/column/{columnId}/add-card-button"
  | .kanbanCreateCard => "/kanban/card"
  | .kanbanGetCard id => s!"/kanban/card/{id}"
  | .kanbanEditCardForm id => s!"/kanban/card/{id}/edit"
  | .kanbanUpdateCard id => s!"/kanban/card/{id}"
  | .kanbanDeleteCard id => s!"/kanban/card/{id}"
  | .kanbanMoveCard id => s!"/kanban/card/{id}/move"
  | .kanbanReorderCard id => s!"/kanban/card/{id}/reorder"
  | .staticJs name => s!"/js/{name}"

/-- Convert route to string (alias for path) -/
instance : ToString Route where
  toString := path

/-- HasPath instance for type-safe HTMX attributes -/
instance : Scribe.HasPath Route where
  path := path

end Route

end HomebaseApp
