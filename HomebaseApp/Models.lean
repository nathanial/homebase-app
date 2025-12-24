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

end HomebaseApp.Models
