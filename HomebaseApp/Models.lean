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
def userIsAdmin : Attribute := ⟨":user/is-admin"⟩

-- ============================================================================
-- Database Entity Structures (for makeLedgerEntity)
-- ============================================================================

/-- Database entity for Kanban boards. -/
structure DbBoard where
  id : Nat               -- Derived from EntityId, skipped in attributes
  name : String
  order : Nat
  deriving Inhabited

/-- Database entity for Kanban columns. -/
structure DbColumn where
  id : Nat               -- Derived from EntityId, skipped in attributes
  name : String
  order : Nat
  board : EntityId       -- Reference to parent board
  deriving Inhabited

/-- Database entity for Kanban cards. The id field is the EntityId, not stored as an attribute. -/
structure DbCard where
  id : Nat               -- Derived from EntityId, skipped in attributes
  title : String
  description : String
  labels : String
  order : Nat
  column : EntityId      -- Reference to parent column
  deriving Inhabited

-- ============================================================================
-- Chat Entity Structures
-- ============================================================================

/-- Database entity for Chat threads. -/
structure DbChatThread where
  id : Nat               -- Derived from EntityId, skipped in attributes
  title : String
  createdAt : Nat        -- milliseconds since epoch
  deriving Inhabited

/-- Database entity for Chat messages. -/
structure DbChatMessage where
  id : Nat               -- Derived from EntityId, skipped in attributes
  content : String
  timestamp : Nat        -- milliseconds since epoch
  thread : EntityId      -- Reference to parent thread
  user : EntityId        -- Reference to user who sent message
  deriving Inhabited

/-- Database entity for Chat message attachments (files). -/
structure DbChatAttachment where
  id : Nat               -- Derived from EntityId, skipped in attributes
  fileName : String      -- Original filename
  storedPath : String    -- Path in data/uploads/
  mimeType : String      -- MIME type (image/jpeg, etc.)
  fileSize : Nat         -- Size in bytes
  uploadedAt : Nat       -- milliseconds since epoch
  message : EntityId     -- Reference to parent message
  deriving Inhabited

end HomebaseApp.Models
