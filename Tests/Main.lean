/-
  Tests.Main - Test runner entry point
-/

import Crucible
import HomebaseApp.Tests.Kanban
import HomebaseApp.Tests.EntityPull

open Crucible

def main : IO UInt32 := runAllSuites
