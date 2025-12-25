/-
  HomebaseApp.Models - Entity attribute definitions

  Defines the Ledger attributes for Users, Kanban, and other sections.
-/
import Ledger

namespace HomebaseApp.Models

open Ledger

-- User attributes
def userEmail : Attribute := ⟨":user/email"⟩
def userPasswordHash : Attribute := ⟨":user/password-hash"⟩
def userName : Attribute := ⟨":user/name"⟩

-- Kanban Column attributes
def columnName : Attribute := ⟨":column/name"⟩
def columnOrder : Attribute := ⟨":column/order"⟩

-- Kanban Card attributes
def cardTitle : Attribute := ⟨":card/title"⟩
def cardDescription : Attribute := ⟨":card/description"⟩
def cardColumn : Attribute := ⟨":card/column"⟩
def cardOrder : Attribute := ⟨":card/order"⟩
def cardLabels : Attribute := ⟨":card/labels"⟩

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
