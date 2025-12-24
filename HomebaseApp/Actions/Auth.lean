/-
  HomebaseApp.Actions.Auth - Authentication actions (login, register, logout)
-/
import Loom
import Ledger
import HomebaseApp.Models
import HomebaseApp.Helpers
import HomebaseApp.Views.Auth

namespace HomebaseApp.Actions.Auth

open Loom
open Ledger
open HomebaseApp.Models
open HomebaseApp.Helpers

/-- Show login form -/
def loginForm : Action := fun ctx => do
  if isLoggedIn ctx then
    Action.redirect "/" ctx
  else
    let html := HomebaseApp.Views.Auth.renderLogin ctx
    Action.html html ctx

/-- Process login -/
def login : Action := fun ctx => do
  let email := ctx.paramD "email" ""
  let password := ctx.paramD "password" ""

  if email.isEmpty || password.isEmpty then
    let ctx := ctx.withFlash fun f => f.set "error" "Email and password are required"
    return ← Action.redirect "/login" ctx

  match findUserByEmail ctx email with
  | none =>
    let ctx := ctx.withFlash fun f => f.set "error" "Invalid email or password"
    Action.redirect "/login" ctx
  | some userId =>
    let storedHash := getAttrString ctx userId userPasswordHash
    let inputHash := hashPassword password ctx.config.secretKey
    match storedHash with
    | some hash =>
      if hash == inputHash then
        let userName := (getAttrString ctx userId userName).getD "User"
        let ctx := ctx.withSession fun s =>
          s.set "user_id" (toString userId.id)
           |>.set "user_name" userName
        let ctx := ctx.withFlash fun f => f.set "success" s!"Welcome back, {userName}!"
        Action.redirect "/" ctx
      else
        let ctx := ctx.withFlash fun f => f.set "error" "Invalid email or password"
        Action.redirect "/login" ctx
    | none =>
      let ctx := ctx.withFlash fun f => f.set "error" "Invalid email or password"
      Action.redirect "/login" ctx

/-- Show register form -/
def registerForm : Action := fun ctx => do
  if isLoggedIn ctx then
    Action.redirect "/" ctx
  else
    let html := HomebaseApp.Views.Auth.renderRegister ctx
    Action.html html ctx

/-- Process registration -/
def register : Action := fun ctx => do
  let name := ctx.paramD "name" ""
  let email := ctx.paramD "email" ""
  let password := ctx.paramD "password" ""

  if name.isEmpty || email.isEmpty || password.isEmpty then
    let ctx := ctx.withFlash fun f => f.set "error" "All fields are required"
    return ← Action.redirect "/register" ctx

  match findUserByEmail ctx email with
  | some _ =>
    let ctx := ctx.withFlash fun f => f.set "error" "Email already registered"
    Action.redirect "/register" ctx
  | none =>
    match ctx.allocEntityId with
    | none =>
      let ctx := ctx.withFlash fun f => f.set "error" "Database not available"
      Action.redirect "/register" ctx
    | some (userId, ctx) =>
      let passwordHash := hashPassword password ctx.config.secretKey
      let tx : Transaction := [
        .add userId userName (.string name),
        .add userId userEmail (.string email),
        .add userId userPasswordHash (.string passwordHash)
      ]
      match ← ctx.transact tx with
      | Except.ok ctx =>
        let ctx := ctx.withSession fun s =>
          s.set "user_id" (toString userId.id)
           |>.set "user_name" name
        let ctx := ctx.withFlash fun f => f.set "success" s!"Welcome, {name}! Your account has been created."
        Action.redirect "/" ctx
      | Except.error e =>
        let ctx := ctx.withFlash fun f => f.set "error" s!"Failed to create account: {e}"
        Action.redirect "/register" ctx

/-- Process logout -/
def logout : Action := fun ctx => do
  let ctx := ctx.withSession fun s => s.clear
  let ctx := ctx.withFlash fun f => f.set "info" "You have been logged out"
  Action.redirect "/" ctx

end HomebaseApp.Actions.Auth
