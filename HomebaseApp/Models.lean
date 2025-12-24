/-
  HomebaseApp.Models - Entity attribute definitions

  Defines the Ledger attributes for Users.
  Each section can add its own attributes as needed.
-/
import Ledger

namespace HomebaseApp.Models

open Ledger

-- User attributes
def userEmail : Attribute := ⟨":user/email"⟩
def userPasswordHash : Attribute := ⟨":user/password-hash"⟩
def userName : Attribute := ⟨":user/name"⟩

end HomebaseApp.Models
