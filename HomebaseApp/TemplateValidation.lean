/-
  HomebaseApp.TemplateValidation - Compile-time template validation

  This module provides a macro that validates all Stencil templates at compile time.
  If any template fails to parse, compilation will fail with a clear error message.
-/
import Stencil
import Lean

namespace HomebaseApp.TemplateValidation

open Lean Elab Command Term Meta

/-- Result of validating a single template -/
structure ValidationResult where
  path : String
  success : Bool
  error : Option String
  deriving Repr

/-- Recursively list all files in a directory -/
partial def walkDir (dir : System.FilePath) : IO (List System.FilePath) := do
  let mut files : List System.FilePath := []
  if ← dir.isDir then
    for entry in ← dir.readDir do
      if ← entry.path.isDir then
        let subFiles ← walkDir entry.path
        files := files ++ subFiles
      else
        files := entry.path :: files
  pure files

/-- Validate a single template file -/
def validateTemplate (path : System.FilePath) : IO ValidationResult := do
  let pathStr := path.toString
  let content ← IO.FS.readFile path
  match Stencil.parse content with
  | .ok _ => pure { path := pathStr, success := true, error := none }
  | .error e => pure { path := pathStr, success := false, error := some (toString e) }

/-- Validate all templates in a directory -/
def validateAllTemplates (templateDir : String) (extension : String) : IO (List ValidationResult) := do
  let dir := System.FilePath.mk templateDir
  if !(← dir.pathExists) then
    return [{ path := templateDir, success := false, error := some "Template directory does not exist" }]

  let allFiles ← walkDir dir
  let templateFiles := allFiles.filter fun path =>
    path.toString.endsWith extension

  let mut results : List ValidationResult := []
  for path in templateFiles do
    let result ← validateTemplate path
    results := result :: results

  pure results

/-- Format validation errors for display -/
def formatErrors (results : List ValidationResult) : String :=
  let errors := results.filter (!·.success)
  if errors.isEmpty then
    "All templates valid"
  else
    let errorMsgs := errors.map fun r =>
      s!"  - {r.path}: {r.error.getD "unknown error"}"
    s!"Template validation failed:\n{String.intercalate "\n" errorMsgs}"

/-- Command to validate templates at compile time -/
elab "#validate_templates" dir:str ext:str : command => do
  let dirStr := dir.getString
  let extStr := ext.getString
  let results ← validateAllTemplates dirStr extStr
  let errors := results.filter (!·.success)

  if !errors.isEmpty then
    let errorMsg := formatErrors results
    throwError errorMsg
  else
    logInfo s!"Validated {results.length} templates successfully"

/-- Syntax for validating templates with default settings -/
macro "#validate_stencil_templates" : command =>
  `(#validate_templates "templates" ".html.hbs")

end HomebaseApp.TemplateValidation
