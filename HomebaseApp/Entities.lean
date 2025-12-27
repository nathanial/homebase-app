/-
  HomebaseApp.Entities - Generated entity helpers using makeLedgerEntity

  This file uses Ledger's derive handler to auto-generate database access code
  for the entity structures defined in Models.lean.
-/
import Ledger
import HomebaseApp.Models

open Ledger.Derive
open HomebaseApp.Models

-- Generate entity helpers (must be outside namespace blocks)
-- Use attrPrefix to match existing attribute names in the database
-- Use attrCasing := kebab for DbUser to match existing data (e.g., :user/password-hash)
makeLedgerEntity DbUser (attrPrefix := "user") (attrCasing := kebab)
makeLedgerEntity DbBoard (attrPrefix := "board")
makeLedgerEntity DbColumn (attrPrefix := "column")
makeLedgerEntity DbCard (attrPrefix := "card")
makeLedgerEntity DbChatThread (attrPrefix := "chat-thread")
makeLedgerEntity DbChatMessage (attrPrefix := "chat-message")
makeLedgerEntity DbChatAttachment (attrPrefix := "chat-attachment")
makeLedgerEntity DbTimeEntry (attrPrefix := "time-entry")
makeLedgerEntity DbTimer (attrPrefix := "timer")
makeLedgerEntity DbGalleryItem (attrPrefix := "gallery-item")
makeLedgerEntity DbNotebook (attrPrefix := "notebook")
makeLedgerEntity DbNote (attrPrefix := "note")
makeLedgerEntity DbHealthEntry (attrPrefix := "health-entry")
makeLedgerEntity DbRecipe (attrPrefix := "recipe")
makeLedgerEntity DbNewsItem (attrPrefix := "news-item")

namespace HomebaseApp.Entities
-- Re-export for convenience
end HomebaseApp.Entities
