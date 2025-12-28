import Lake
open Lake DSL

package homebaseApp where
  version := v!"0.1.0"

require loom from ".." / "loom"
require crucible from ".." / "crucible"
require chronicle from ".." / "chronicle"
require staple from ".." / "staple"
require wisp from ".." / "wisp"

-- OpenSSL linking (required by citadel's TLS support via loom)
-- Lake doesn't propagate moreLinkArgs from dependencies, so we must add them here
def opensslLinkArgs : Array String :=
  #["-L/opt/homebrew/opt/openssl@3/lib", "-lssl", "-lcrypto"]

-- Curl linking (required by wisp HTTP client)
def curlLinkArgs : Array String :=
  #["-L/opt/homebrew/opt/curl/lib",
    "-L/opt/homebrew/lib",
    "-L/usr/local/lib",
    "-lcurl",
    "-Wl,-rpath,/opt/homebrew/opt/curl/lib",
    "-Wl,-rpath,/opt/homebrew/lib",
    "-Wl,-rpath,/usr/local/lib"]

def allLinkArgs : Array String := opensslLinkArgs ++ curlLinkArgs

@[default_target]
lean_lib HomebaseApp where
  roots := #[`HomebaseApp]
  moreLinkArgs := allLinkArgs

lean_exe homebaseApp where
  root := `HomebaseApp.Main
  moreLinkArgs := allLinkArgs

-- Test executable
@[test_driver]
lean_exe tests where
  root := `Tests.Main
  moreLinkArgs := allLinkArgs
