/-
  Tests.Main - Test runner entry point
-/

import Crucible
import HomebaseApp.Tests.Kanban

open Crucible

def main : IO UInt32 := runAllSuites
