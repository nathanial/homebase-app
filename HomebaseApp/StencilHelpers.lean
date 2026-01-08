/-
  HomebaseApp.StencilHelpers - Helpers for Stencil template rendering
-/
import Loom
import Loom.Stencil
import Stencil
import HomebaseApp.Shared

namespace HomebaseApp.StencilHelpers

open Loom
open HomebaseApp.Shared (isLoggedIn isAdmin)

/-- Page identifiers for sidebar active state -/
inductive PageId where
  | home | chat | notebook | time | health | recipes | kanban | gallery | news | novels | admin
  deriving BEq

/-- Build common layout context data -/
def layoutContext (ctx : Context) (title : String) (currentPage : PageId) : Stencil.Value :=
  .object #[
    ("title", .string title),
    ("userName", match ctx.session.get "user_name" with
      | some name => .string name
      | none => .null),
    ("showAdmin", .bool (isAdmin ctx)),
    -- Page flags for sidebar active state
    ("isHome", .bool (currentPage == .home)),
    ("isChat", .bool (currentPage == .chat)),
    ("isNotebook", .bool (currentPage == .notebook)),
    ("isTime", .bool (currentPage == .time)),
    ("isHealth", .bool (currentPage == .health)),
    ("isRecipes", .bool (currentPage == .recipes)),
    ("isKanban", .bool (currentPage == .kanban)),
    ("isGallery", .bool (currentPage == .gallery)),
    ("isNews", .bool (currentPage == .news)),
    ("isNovels", .bool (currentPage == .novels)),
    ("isAdmin", .bool (currentPage == .admin))
  ]

/-- Merge layout context with page-specific data -/
def mergeContext (layout : Stencil.Value) (pageData : Stencil.Value) : Stencil.Value :=
  match layout, pageData with
  | .object layoutFields, .object pageFields =>
    .object (layoutFields ++ pageFields)
  | .object layoutFields, .null =>
    .object layoutFields
  | _, _ => layout

/-- Build full context for a page -/
def pageContext (ctx : Context) (title : String) (currentPage : PageId)
    (data : Stencil.Value := .null) : Stencil.Value :=
  mergeContext (layoutContext ctx title currentPage) data

end HomebaseApp.StencilHelpers
