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
  -- Chat pages
  | chat
  | chatEvents                        -- SSE endpoint
  | chatThread (id : Nat)             -- View thread
  | chatCreateThread                  -- Create thread
  | chatDeleteThread (id : Nat)       -- Delete thread
  | chatAddMessage (threadId : Nat)   -- Add message
  | chatSearch                        -- Search
  | chatNewThreadForm                 -- New thread modal
  | chatEditThreadForm (id : Nat)     -- Edit thread modal
  | chatUpdateThread (id : Nat)       -- Update thread
  -- Chat file upload routes
  | chatUploadAttachment (threadId : Nat)  -- Upload file to thread
  | chatServeAttachment (filename : String) -- Serve uploaded file
  | chatDeleteAttachment (id : Nat)        -- Delete attachment
  -- Admin routes
  | admin                             -- User list
  | adminUser (id : Nat)              -- View user
  | adminCreateUser                   -- Create user form
  | adminStoreUser                    -- Create user POST
  | adminEditUser (id : Nat)          -- Edit user form
  | adminUpdateUser (id : Nat)        -- Update user PUT
  | adminDeleteUser (id : Nat)        -- Delete user
  -- Static files
  | staticJs (name : String)
  | staticCss (name : String)
  deriving Repr

namespace Route

/-- Convert a route to its URL path -/
def path : Route → String
  | .home => "/"
  | .login => "/login"
  | .register => "/register"
  | .logout => "/logout"
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
  -- Chat routes
  | .chat => "/chat"
  | .chatEvents => "/events/chat"
  | .chatThread id => s!"/chat/thread/{id}"
  | .chatCreateThread => "/chat/thread"
  | .chatDeleteThread id => s!"/chat/thread/{id}"
  | .chatAddMessage threadId => s!"/chat/thread/{threadId}/message"
  | .chatSearch => "/chat/search"
  | .chatNewThreadForm => "/chat/new-thread-form"
  | .chatEditThreadForm id => s!"/chat/thread/{id}/edit"
  | .chatUpdateThread id => s!"/chat/thread/{id}"
  -- Chat file upload routes
  | .chatUploadAttachment threadId => s!"/chat/thread/{threadId}/upload"
  | .chatServeAttachment filename => s!"/uploads/{filename}"
  | .chatDeleteAttachment id => s!"/chat/attachment/{id}"
  -- Admin routes
  | .admin => "/admin"
  | .adminUser id => s!"/admin/user/{id}"
  | .adminCreateUser => "/admin/user/new"
  | .adminStoreUser => "/admin/user"
  | .adminEditUser id => s!"/admin/user/{id}/edit"
  | .adminUpdateUser id => s!"/admin/user/{id}"
  | .adminDeleteUser id => s!"/admin/user/{id}"
  -- Static files
  | .staticJs name => s!"/js/{name}"
  | .staticCss name => s!"/css/{name}"

/-- Convert route to string (alias for path) -/
instance : ToString Route where
  toString := path

/-- HasPath instance for type-safe HTMX attributes -/
instance : Scribe.HasPath Route where
  path := path

end Route

end HomebaseApp
