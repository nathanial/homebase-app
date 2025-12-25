/-
  HomebaseApp.Entities - Generated entity helpers using makeLedgerEntity

  This file uses Ledger's derive handler to auto-generate database access code
  for the entity structures defined in Models.lean.
-/
import Ledger
import HomebaseApp.Models
import HomebaseApp.Views.Kanban

open Ledger.Derive
open HomebaseApp.Models

-- Generate entity helpers (must be outside namespace blocks)
-- Use attrPrefix to match existing attribute names in the database
makeLedgerEntity DbCard (attrPrefix := "card")
makeLedgerEntity DbColumn (attrPrefix := "column")

-- ============================================================================
-- Conversion helpers (in struct namespace for dot notation)
-- ============================================================================

namespace HomebaseApp.Models.DbCard

open HomebaseApp.Views.Kanban

/-- Convert a DbCard to a view Card (drops the column reference) -/
def toViewCard (c : DbCard) : Card :=
  { id := c.id
  , title := c.title
  , description := c.description
  , labels := c.labels
  , order := c.order }

end HomebaseApp.Models.DbCard

namespace HomebaseApp.Models.DbColumn

open HomebaseApp.Views.Kanban

/-- Convert a DbColumn to a view Column with cards -/
def toViewColumn (c : DbColumn) (cards : List Card) : Column :=
  { id := c.id
  , name := c.name
  , order := c.order
  , cards := cards }

end HomebaseApp.Models.DbColumn

namespace HomebaseApp.Entities
-- Re-export for convenience
end HomebaseApp.Entities
