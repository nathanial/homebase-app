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
makeLedgerEntity DbCard (attrPrefix := "card")
makeLedgerEntity DbColumn (attrPrefix := "column")
makeLedgerEntity DbChatThread (attrPrefix := "chat-thread")
makeLedgerEntity DbChatMessage (attrPrefix := "chat-message")
makeLedgerEntity DbChatAttachment (attrPrefix := "chat-attachment")

namespace HomebaseApp.Entities
-- Re-export for convenience
end HomebaseApp.Entities
