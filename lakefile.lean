import Lake
open Lake DSL

package homebaseApp where
  version := v!"0.1.0"

require loom from git "https://github.com/nathanial/loom" @ "v0.0.6"
-- require loom from "../../web/loom"

require crucible from git "https://github.com/nathanial/crucible" @ "v0.0.1"
-- require crucible from "../../testing/crucible"

require chronicle from git "https://github.com/nathanial/chronicle" @ "v0.0.1"
-- require chronicle from "../../web/chronicle"

require staple from git "https://github.com/nathanial/staple" @ "v0.0.2"
-- require staple from "../../util/staple"

require wisp from git "https://github.com/nathanial/wisp" @ "v0.0.1"
-- require wisp from "../../network/wisp"

require crypt from git "https://github.com/nathanial/crypt" @ "v0.0.1"
-- require crypt from "../../util/crypt"

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

-- Sodium linking (required by crypt)
def sodiumLinkArgs : Array String :=
  #["-L/opt/homebrew/lib", "-lsodium"]

def allLinkArgs : Array String := opensslLinkArgs ++ curlLinkArgs ++ sodiumLinkArgs

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
