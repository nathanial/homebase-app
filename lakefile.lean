import Lake
open Lake DSL

package homebaseApp where
  version := v!"0.1.0"

require loom from ".." / "loom"
require crucible from ".." / "crucible"
require chronicle from ".." / "chronicle"
require staple from ".." / "staple"

@[default_target]
lean_lib HomebaseApp where
  roots := #[`HomebaseApp]

lean_exe homebaseApp where
  root := `HomebaseApp.Main

-- Test executable
@[test_driver]
lean_exe tests where
  root := `Tests.Main
