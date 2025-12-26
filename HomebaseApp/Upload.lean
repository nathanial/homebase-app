/-
  HomebaseApp.Upload - File upload storage utilities
-/
import Staple

namespace HomebaseApp.Upload

open Staple (String.containsSubstr)

/-- Base upload directory -/
def uploadDir : System.FilePath := "data/uploads"

/-- Maximum file size (10MB) -/
def maxFileSize : Nat := 10 * 1024 * 1024

/-- Allowed MIME types for chat -/
def allowedMimeTypes : List String := [
  "image/jpeg", "image/png", "image/gif", "image/webp",
  "application/pdf", "text/plain"
]

/-- Check if MIME type is allowed -/
def isAllowedType (mimeType : String) : Bool :=
  allowedMimeTypes.any fun allowed =>
    mimeType.startsWith allowed

/-- Convert a Nat to a hex string (up to 16 hex digits) -/
private def natToHex (n : Nat) : String :=
  let hexDigits := "0123456789abcdef"
  if n == 0 then "0"
  else
    -- Use fuel to limit recursion depth (16 hex digits = 64 bits)
    let rec loop (n : Nat) (fuel : Nat) (acc : List Char) : List Char :=
      if h : fuel == 0 || n == 0 then acc
      else
        let digit := n % 16
        let char := hexDigits.get! ⟨digit⟩
        loop (n / 16) (fuel - 1) (char :: acc)
    termination_by fuel
    decreasing_by simp_wf; simp_all; omega
    String.mk (loop n 16 [])

/-- Generate a unique ID using nanoseconds + random component -/
def generateUniqueId : IO String := do
  let nanos ← IO.monoNanosNow
  -- Simple pseudo-random using time
  let rand := (nanos % 1000000).toUInt64
  pure s!"{natToHex nanos.toUInt64.toNat}-{natToHex rand.toNat}"

/-- Sanitize filename - remove path separators and suspicious characters -/
def sanitizeFilename (name : String) : String :=
  let clean := name.toList.filter fun c =>
    c.isAlphanum || c == '.' || c == '-' || c == '_'
  if clean.isEmpty then "upload" else String.ofList clean

/-- Get file extension from filename -/
def getExtension (filename : String) : String :=
  match filename.splitOn "." with
  | parts =>
    if parts.length > 1 then
      parts.getLast!
    else
      ""

/-- Ensure upload directory exists -/
def ensureUploadDir : IO Unit := do
  IO.FS.createDirAll uploadDir

/-- Check if a path is safe (no path traversal) -/
def isSafePath (path : String) : Bool :=
  !String.containsSubstr path ".." && !path.startsWith "/" && !String.containsSubstr path "~"

/-- Store an uploaded file, return the stored filename -/
def storeFile (content : ByteArray) (originalName : String) : IO String := do
  ensureUploadDir
  let uniqueId ← generateUniqueId
  let ext := getExtension (sanitizeFilename originalName)
  let storedName := if ext.isEmpty then uniqueId else s!"{uniqueId}.{ext}"
  let filePath := uploadDir / storedName
  IO.FS.writeBinFile filePath content
  pure storedName

/-- Delete a file from storage -/
def deleteFile (storedPath : String) : IO Bool := do
  if !isSafePath storedPath then
    return false
  let filePath := uploadDir / storedPath
  try
    IO.FS.removeFile filePath
    pure true
  catch _ =>
    pure false

/-- Read a file from storage -/
def readFile (storedPath : String) : IO (Option ByteArray) := do
  if !isSafePath storedPath then
    return none
  let filePath := uploadDir / storedPath
  try
    let content ← IO.FS.readBinFile filePath
    pure (some content)
  catch _ =>
    pure none

/-- Get MIME type from file extension -/
def mimeTypeForExtension (ext : String) : String :=
  match ext.toLower with
  | "jpg" | "jpeg" => "image/jpeg"
  | "png" => "image/png"
  | "gif" => "image/gif"
  | "webp" => "image/webp"
  | "pdf" => "application/pdf"
  | "txt" => "text/plain"
  | "html" => "text/html"
  | "css" => "text/css"
  | "js" => "application/javascript"
  | "json" => "application/json"
  | _ => "application/octet-stream"

/-- Get MIME type for a stored file -/
def mimeTypeForFile (storedPath : String) : String :=
  let ext := getExtension storedPath
  mimeTypeForExtension ext

end HomebaseApp.Upload
