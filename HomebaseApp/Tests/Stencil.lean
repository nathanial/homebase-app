/-
  HomebaseApp.Tests.Stencil - Tests for Stencil template loading
-/
import Crucible
import Loom.Stencil

namespace HomebaseApp.Tests.Stencil

open Crucible
open Loom.Stencil

testSuite "Stencil Template Discovery"

test "discover loads kanban partials with correct names" := do
  let config : Config := { templateDir := "templates", extension := ".html.hbs", hotReload := false }
  let manager ← Manager.discover config

  -- Print all discovered partials for debugging
  IO.println s!"Discovered {manager.partialCount} partials:"

  -- Check for specific kanban partials
  let cardPartial := manager.getPartial "kanban/_card"
  let columnPartial := manager.getPartial "kanban/_column"

  -- Also try without underscore to see what's registered
  let cardNoUnderscore := manager.getPartial "kanban/card"
  let columnNoUnderscore := manager.getPartial "kanban/column"

  IO.println s!"  kanban/_card: {cardPartial.isSome}"
  IO.println s!"  kanban/_column: {columnPartial.isSome}"
  IO.println s!"  kanban/card (no underscore): {cardNoUnderscore.isSome}"
  IO.println s!"  kanban/column (no underscore): {columnNoUnderscore.isSome}"

  -- At least one should exist
  shouldSatisfy (cardPartial.isSome || cardNoUnderscore.isSome) "kanban card partial should exist"
  shouldSatisfy (columnPartial.isSome || columnNoUnderscore.isSome) "kanban column partial should exist"

test "discover loads chat partials with correct names" := do
  let config : Config := { templateDir := "templates", extension := ".html.hbs", hotReload := false }
  let manager ← Manager.discover config

  let threadAreaPartial := manager.getPartial "chat/_thread-area"
  let threadAreaNoUnderscore := manager.getPartial "chat/thread-area"

  IO.println s!"  chat/_thread-area: {threadAreaPartial.isSome}"
  IO.println s!"  chat/thread-area (no underscore): {threadAreaNoUnderscore.isSome}"

  shouldSatisfy (threadAreaPartial.isSome || threadAreaNoUnderscore.isSome) "chat thread-area partial should exist"

test "list all registered partials" := do
  let config : Config := { templateDir := "templates", extension := ".html.hbs", hotReload := false, autoRegisterPartials := true }
  let manager ← Manager.discover config

  IO.println s!"\nTotal partials: {manager.partialCount}"
  IO.println s!"Total templates: {manager.templateCount}"
  IO.println s!"Total layouts: {manager.layoutCount}"

  -- This test always passes - it's just for debugging
  true ≡ true

end HomebaseApp.Tests.Stencil
