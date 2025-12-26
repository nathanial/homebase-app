/-
  HomebaseApp.Entities - Generated entity helpers using makeLedgerEntity

  This file uses Ledger's derive handler to auto-generate database access code
  for the entity structures defined in Models.lean.
-/
import Ledger
import HomebaseApp.Models
import HomebaseApp.Views.Kanban
import HomebaseApp.Views.Chat

open Ledger.Derive
open HomebaseApp.Models

-- Generate entity helpers (must be outside namespace blocks)
-- Use attrPrefix to match existing attribute names in the database
makeLedgerEntity DbCard (attrPrefix := "card")
makeLedgerEntity DbColumn (attrPrefix := "column")
makeLedgerEntity DbChatThread (attrPrefix := "chat-thread")
makeLedgerEntity DbChatMessage (attrPrefix := "chat-message")
makeLedgerEntity DbChatAttachment (attrPrefix := "chat-attachment")

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

namespace HomebaseApp.Models.DbChatThread

open HomebaseApp.Views.Chat

/-- Convert a DbChatThread to a view Thread with message info -/
def toViewThread (t : DbChatThread) (messageCount : Nat) (lastMessage : Option String) : Thread :=
  { id := t.id
  , title := t.title
  , createdAt := t.createdAt
  , messageCount := messageCount
  , lastMessage := lastMessage }

end HomebaseApp.Models.DbChatThread

namespace HomebaseApp.Models.DbChatMessage

open HomebaseApp.Views.Chat

/-- Convert a DbChatMessage to a view Message -/
def toViewMessage (m : DbChatMessage) (userName : String) (attachments : List Attachment := []) : Message :=
  { id := m.id
  , content := m.content
  , timestamp := m.timestamp
  , userName := userName
  , attachments := attachments }

end HomebaseApp.Models.DbChatMessage

namespace HomebaseApp.Models.DbChatAttachment

open HomebaseApp.Views.Chat

/-- Convert a DbChatAttachment to a view Attachment -/
def toViewAttachment (a : DbChatAttachment) : Attachment :=
  { id := a.id
  , fileName := a.fileName
  , mimeType := a.mimeType
  , fileSize := a.fileSize
  , url := s!"/uploads/{a.storedPath}" }

end HomebaseApp.Models.DbChatAttachment

namespace HomebaseApp.Entities
-- Re-export for convenience
end HomebaseApp.Entities
