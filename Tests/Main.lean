/-
  Tests.Main - Test runner entry point
-/

import Crucible
import HomebaseApp.Tests.Kanban
import HomebaseApp.Tests.EntityPull
import HomebaseApp.Tests.Time
import HomebaseApp.Tests.Stencil

open Crucible

def main : IO UInt32 := runAllSuites
