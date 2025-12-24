import Lake
open Lake DSL

package homebaseApp where
  version := v!"0.1.0"

require loom from ".." / "loom"
require crucible from ".." / "crucible"

@[default_target]
lean_lib HomebaseApp where
  roots := #[`HomebaseApp]

lean_exe homebaseApp where
  root := `HomebaseApp.Main
