/-
  HomebaseApp.Models - Entity structures and attribute definitions

  Defines entity structures and Ledger attributes for the app.
  Kanban attributes (column/*, card/*) are auto-generated via makeLedgerEntity.
-/
import Ledger

namespace HomebaseApp.Models

open Ledger

-- User attributes (no DbUser structure yet, so defined manually)
def userEmail : Attribute := ⟨":user/email"⟩
def userPasswordHash : Attribute := ⟨":user/password-hash"⟩
def userName : Attribute := ⟨":user/name"⟩

-- ============================================================================
-- Database Entity Structures (for makeLedgerEntity)
-- ============================================================================

/-- Database entity for Kanban cards. The id field is the EntityId, not stored as an attribute. -/
structure DbCard where
  id : Nat               -- Derived from EntityId, skipped in attributes
  title : String
  description : String
  labels : String
  order : Nat
  column : EntityId      -- Reference to parent column
  deriving Inhabited

/-- Database entity for Kanban columns. -/
structure DbColumn where
  id : Nat               -- Derived from EntityId, skipped in attributes
  name : String
  order : Nat
  deriving Inhabited

end HomebaseApp.Models
