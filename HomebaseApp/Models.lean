/-
  HomebaseApp.Models - Entity structures and attribute definitions

  Defines entity structures and Ledger attributes for the app.
  Kanban attributes (column/*, card/*) are auto-generated via makeLedgerEntity.
-/
import Ledger

namespace HomebaseApp.Models

open Ledger

-- Legacy user attributes (kept for backward compatibility, DbUser uses these via attrPrefix)
def userEmail : Attribute := ⟨":user/email"⟩
def userPasswordHash : Attribute := ⟨":user/password-hash"⟩
def userName : Attribute := ⟨":user/name"⟩
def userIsAdmin : Attribute := ⟨":user/is-admin"⟩

/-- Database entity for users. -/
structure DbUser where
  id : Nat               -- Derived from EntityId, skipped in attributes
  email : String
  passwordHash : String  -- Maps to :user/password-hash
  name : String
  isAdmin : Bool         -- Maps to :user/is-admin
  deriving Inhabited

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

-- ============================================================================
-- Time Tracking Entity Structures
-- ============================================================================

/-- Time entry (completed time record). -/
structure DbTimeEntry where
  id : Nat               -- Derived from EntityId, skipped in attributes
  description : String   -- What was worked on
  startTime : Nat        -- milliseconds since epoch
  endTime : Nat          -- milliseconds since epoch
  duration : Nat         -- duration in seconds (computed for quick access)
  category : String      -- e.g., "Work", "Personal", "Learning"
  user : EntityId        -- Reference to user who logged the time
  deriving Inhabited

/-- Active timer (running time entry, not yet completed). -/
structure DbTimer where
  id : Nat               -- Derived from EntityId, skipped in attributes
  description : String   -- What is being worked on
  startTime : Nat        -- When timer started (milliseconds since epoch)
  category : String      -- Timer category
  user : EntityId        -- Reference to user who started the timer
  deriving Inhabited

-- ============================================================================
-- Gallery Entity Structures
-- ============================================================================

/-- Gallery item (photo or file). -/
structure DbGalleryItem where
  id : Nat               -- Derived from EntityId, skipped in attributes
  title : String         -- Display title
  description : String   -- Optional description
  fileName : String      -- Original filename
  storedPath : String    -- Path in data/uploads/
  mimeType : String      -- MIME type
  fileSize : Nat         -- Size in bytes
  uploadedAt : Nat       -- milliseconds since epoch
  user : EntityId        -- Reference to uploader
  deriving Inhabited

-- ============================================================================
-- Notebook Entity Structures
-- ============================================================================

/-- Notebook (folder for organizing notes). -/
structure DbNotebook where
  id : Nat               -- Derived from EntityId, skipped in attributes
  title : String
  createdAt : Nat        -- milliseconds since epoch
  user : EntityId        -- Reference to owner
  deriving Inhabited

/-- Note (markdown content within a notebook). -/
structure DbNote where
  id : Nat               -- Derived from EntityId, skipped in attributes
  title : String
  content : String       -- Markdown content
  notebook : EntityId    -- Reference to parent notebook
  createdAt : Nat
  updatedAt : Nat
  user : EntityId        -- Reference to owner
  deriving Inhabited

-- ============================================================================
-- Health Entity Structures
-- ============================================================================

/-- Health entry (weight, exercise, medication, or general note). -/
structure DbHealthEntry where
  id : Nat               -- Derived from EntityId, skipped in attributes
  entryType : String     -- "weight", "exercise", "medication", "note"
  value : String         -- Numeric or text depending on type
  unit : String          -- "kg", "lbs", "minutes", etc.
  notes : String         -- Additional notes
  recordedAt : Nat       -- Date of measurement (milliseconds since epoch)
  createdAt : Nat
  user : EntityId        -- Reference to owner
  deriving Inhabited

-- ============================================================================
-- Recipe Entity Structures
-- ============================================================================

/-- Recipe with ingredients and instructions. -/
structure DbRecipe where
  id : Nat               -- Derived from EntityId, skipped in attributes
  title : String
  description : String   -- Short description
  ingredients : String   -- Newline-separated list
  instructions : String  -- Markdown or plain text steps
  prepTime : Nat         -- Minutes
  cookTime : Nat         -- Minutes
  servings : Nat
  category : String      -- "Breakfast", "Lunch", "Dinner", "Dessert", "Snack"
  createdAt : Nat
  updatedAt : Nat
  user : EntityId        -- Reference to owner
  deriving Inhabited

-- ============================================================================
-- News Entity Structures
-- ============================================================================

/-- News item (link with metadata). -/
structure DbNewsItem where
  id : Nat               -- Derived from EntityId, skipped in attributes
  title : String
  url : String
  description : String   -- Optional summary
  source : String        -- Domain or feed name
  category : String      -- User-defined category
  isRead : Bool
  isSaved : Bool         -- Bookmark status
  addedAt : Nat          -- milliseconds since epoch
  user : EntityId        -- Reference to owner
  deriving Inhabited

end HomebaseApp.Models
