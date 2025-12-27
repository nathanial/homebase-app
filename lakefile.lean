import Lake
open Lake DSL

package homebaseApp where
  version := v!"0.1.0"

require loom from ".." / "loom"
require crucible from ".." / "crucible"
require chronicle from ".." / "chronicle"
require staple from ".." / "staple"

-- OpenSSL linking (required by citadel's TLS support via loom)
-- Lake doesn't propagate moreLinkArgs from dependencies, so we must add them here
def opensslLinkArgs : Array String :=
  #["-L/opt/homebrew/opt/openssl@3/lib", "-lssl", "-lcrypto"]

@[default_target]
lean_lib HomebaseApp where
  roots := #[`HomebaseApp]
  moreLinkArgs := opensslLinkArgs

lean_exe homebaseApp where
  root := `HomebaseApp.Main
  moreLinkArgs := opensslLinkArgs

-- Test executable
@[test_driver]
lean_exe tests where
  root := `Tests.Main
  moreLinkArgs := opensslLinkArgs
