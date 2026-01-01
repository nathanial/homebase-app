/-
  HomebaseApp.Pages.Recipes - Recipe storage with ingredients and instructions
-/
import Scribe
import Loom
import Loom.SSE
import Loom.Stencil
import Stencil
import Ledger
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Helpers
import HomebaseApp.Middleware
import HomebaseApp.StencilHelpers

namespace HomebaseApp.Pages

open Scribe
open Loom hiding Action
open Loom.Page
open Loom.ActionM
open Loom.AuditTxM (audit)
open Loom.Json
open Ledger
open HomebaseApp.Shared hiding isLoggedIn isAdmin
open HomebaseApp.Models
open HomebaseApp.Entities
open HomebaseApp.Helpers
open HomebaseApp.StencilHelpers

/-! ## Constants -/

/-- Recipe category options -/
def recipeCategories : List String :=
  ["Breakfast", "Lunch", "Dinner", "Dessert", "Snack", "Beverage", "Other"]

/-! ## View Models -/

/-- View model for a recipe -/
structure RecipeView where
  id : Nat
  title : String
  description : String
  ingredients : String
  instructions : String
  prepTime : Nat
  cookTime : Nat
  servings : Nat
  category : String
  createdAt : Nat
  updatedAt : Nat
  deriving Inhabited

/-! ## Stencil Value Helpers -/

/-- Format time in minutes -/
def recipesFormatTime (minutes : Nat) : String :=
  if minutes >= 60 then
    let hours := minutes / 60
    let mins := minutes % 60
    if mins > 0 then s!"{hours}h {mins}m" else s!"{hours}h"
  else if minutes > 0 then s!"{minutes}m"
  else "—"

/-- Get category icon -/
def recipesCategoryIcon (category : String) : String :=
  match category with
  | "Breakfast" => "🍳"
  | "Lunch" => "🥗"
  | "Dinner" => "🍽️"
  | "Dessert" => "🍰"
  | "Snack" => "🍿"
  | "Beverage" => "🥤"
  | _ => "📋"

/-- Parse ingredients/instructions string to list -/
def recipesParseLines (text : String) : List String :=
  text.splitOn "\n" |>.filter (!·.isEmpty)

/-- Convert a RecipeView to Stencil.Value -/
def recipeToValue (recipe : RecipeView) : Stencil.Value :=
  let totalTime := recipe.prepTime + recipe.cookTime
  let ingredientsList := recipesParseLines recipe.ingredients
  let instructionsList := recipesParseLines recipe.instructions
  .object #[
    ("id", .int (Int.ofNat recipe.id)),
    ("title", .string recipe.title),
    ("description", .string recipe.description),
    ("shortDescription", .string (recipe.description.take 100)),
    ("ingredients", .string recipe.ingredients),
    ("instructions", .string recipe.instructions),
    ("ingredientsList", .array (ingredientsList.map .string).toArray),
    ("instructionsList", .array (instructionsList.map .string).toArray),
    ("prepTime", .int (Int.ofNat recipe.prepTime)),
    ("cookTime", .int (Int.ofNat recipe.cookTime)),
    ("servings", .int (Int.ofNat recipe.servings)),
    ("category", .string recipe.category),
    ("icon", .string (recipesCategoryIcon recipe.category)),
    ("hasDescription", .bool (!recipe.description.isEmpty)),
    ("hasPrepTime", .bool (recipe.prepTime > 0)),
    ("hasCookTime", .bool (recipe.cookTime > 0)),
    ("hasTotalTime", .bool (totalTime > 0)),
    ("hasServings", .bool (recipe.servings > 0)),
    ("hasIngredients", .bool (!ingredientsList.isEmpty)),
    ("hasInstructions", .bool (!instructionsList.isEmpty)),
    ("prepTimeFormatted", .string (recipesFormatTime recipe.prepTime)),
    ("cookTimeFormatted", .string (recipesFormatTime recipe.cookTime)),
    ("totalTimeFormatted", .string (recipesFormatTime totalTime)),
    -- Category flags for edit form
    ("isBreakfast", .bool (recipe.category == "Breakfast")),
    ("isLunch", .bool (recipe.category == "Lunch")),
    ("isDinner", .bool (recipe.category == "Dinner")),
    ("isDessert", .bool (recipe.category == "Dessert")),
    ("isSnack", .bool (recipe.category == "Snack")),
    ("isBeverage", .bool (recipe.category == "Beverage")),
    ("isOther", .bool (recipe.category == "Other"))
  ]

/-- Convert a list of recipes to Stencil.Value -/
def recipesToValue (recipes : List RecipeView) : Stencil.Value :=
  .array (recipes.map recipeToValue).toArray

/-! ## Helpers -/

/-- Get current time in milliseconds -/
def recipesGetNowMs : IO Nat := do
  let output ← IO.Process.output { cmd := "date", args := #["+%s"] }
  let seconds := output.stdout.trim.toNat?.getD 0
  return seconds * 1000

/-- Get current user's EntityId -/
def recipesGetCurrentUserEid (ctx : Context) : Option EntityId :=
  match currentUserId ctx with
  | some idStr => idStr.toNat?.map fun n => ⟨n⟩
  | none => none

/-! ## Database Helpers -/

/-- Get all recipes for current user -/
def getRecipes (ctx : Context) : List RecipeView :=
  match ctx.database, recipesGetCurrentUserEid ctx with
  | some db, some userEid =>
    let recipeIds := db.findByAttrValue DbRecipe.attr_user (.ref userEid)
    let recipes := recipeIds.filterMap fun recipeId =>
      match DbRecipe.pull db recipeId with
      | some r =>
        some { id := r.id, title := r.title, description := r.description,
               ingredients := r.ingredients, instructions := r.instructions,
               prepTime := r.prepTime, cookTime := r.cookTime, servings := r.servings,
               category := r.category, createdAt := r.createdAt, updatedAt := r.updatedAt }
      | none => none
    recipes.toArray.qsort (fun a b => a.title < b.title) |>.toList  -- alphabetical
  | _, _ => []

/-- Get recipes filtered by category -/
def getRecipesByCategory (ctx : Context) (category : String) : List RecipeView :=
  let recipes := getRecipes ctx
  recipes.filter (·.category == category)

/-- Get a single recipe by ID -/
def getRecipe (ctx : Context) (recipeId : Nat) : Option RecipeView :=
  match ctx.database with
  | some db =>
    let eid : EntityId := ⟨recipeId⟩
    match DbRecipe.pull db eid with
    | some r =>
      some { id := r.id, title := r.title, description := r.description,
             ingredients := r.ingredients, instructions := r.instructions,
             prepTime := r.prepTime, cookTime := r.cookTime, servings := r.servings,
             category := r.category, createdAt := r.createdAt, updatedAt := r.updatedAt }
    | none => none
  | none => none

/-- Search recipes by title -/
def searchRecipes (ctx : Context) (query : String) : List RecipeView :=
  let recipes := getRecipes ctx
  let queryLower := query.toLower
  recipes.filter fun r => queryLower.isPrefixOf r.title.toLower || r.title.toLower.startsWith queryLower

/-! ## Pages -/

-- Main recipes page
view recipesPage "/recipes" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let filter := ctx.paramD "category" "all"
  let recipes := if filter == "all" then getRecipes ctx else getRecipesByCategory ctx filter
  let data := pageContext ctx "Recipes" PageId.recipes
    (.object #[
      ("recipes", recipesToValue recipes),
      ("hasRecipes", .bool (!recipes.isEmpty)),
      ("filterAll", .bool (filter == "all")),
      ("filterBreakfast", .bool (filter == "Breakfast")),
      ("filterLunch", .bool (filter == "Lunch")),
      ("filterDinner", .bool (filter == "Dinner")),
      ("filterDessert", .bool (filter == "Dessert")),
      ("filterSnack", .bool (filter == "Snack")),
      ("filterBeverage", .bool (filter == "Beverage")),
      ("filterOther", .bool (filter == "Other"))
    ])
  Loom.Stencil.ActionM.renderWithLayout "app" "recipes/index" data

-- View single recipe
view recipeView "/recipes/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getRecipe ctx id with
  | none => notFound "Recipe not found"
  | some recipe =>
    let data := pageContext ctx s!"{recipe.title}" PageId.recipes (recipeToValue recipe)
    Loom.Stencil.ActionM.renderWithLayout "app" "recipes/show" data

-- New recipe form
view recipesNewForm "/recipes/new" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let data := pageContext ctx "New Recipe" PageId.recipes
    (.object #[("csrfToken", .string ctx.csrfToken)])
  Loom.Stencil.ActionM.renderWithLayout "app" "recipes/new" data

-- Edit recipe form
view recipesEditForm "/recipes/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getRecipe ctx id with
  | none => notFound "Recipe not found"
  | some recipe =>
    let data := mergeContext (recipeToValue recipe)
      (.object #[("csrfToken", .string ctx.csrfToken)])
    Loom.Stencil.ActionM.renderWithLayout "app" "recipes/edit" (pageContext ctx s!"Edit {recipe.title}" PageId.recipes data)

/-! ## Actions -/

-- Create recipe
action recipesCreate "/recipes/create" POST [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  let description := ctx.paramD "description" ""
  let ingredients := ctx.paramD "ingredients" ""
  let instructions := ctx.paramD "instructions" ""
  let prepTime := (ctx.paramD "prepTime" "0").toNat?.getD 0
  let cookTime := (ctx.paramD "cookTime" "0").toNat?.getD 0
  let servings := (ctx.paramD "servings" "4").toNat?.getD 4
  let category := ctx.paramD "category" "Other"
  if title.isEmpty then return ← badRequest "Title is required"
  match recipesGetCurrentUserEid ctx with
  | none => redirect "/login"
  | some userEid =>
    let now ← recipesGetNowMs
    let (eid, _) ← withNewEntityAudit! fun eid => do
      let recipe : DbRecipe := {
        id := eid.id.toNat, title := title, description := description,
        ingredients := ingredients, instructions := instructions,
        prepTime := prepTime, cookTime := cookTime, servings := servings,
        category := category, createdAt := now, updatedAt := now, user := userEid
      }
      DbRecipe.TxM.create eid recipe
      audit "CREATE" "recipe" eid.id.toNat [("title", title), ("category", category)]
    let _ ← SSE.publishEvent "recipes" "recipe-created" (jsonStr! { title, category })
    redirect s!"/recipes/{eid.id.toNat}"

-- Update recipe
action recipesUpdate "/recipes/:id" PUT [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  let title := ctx.paramD "title" ""
  let description := ctx.paramD "description" ""
  let ingredients := ctx.paramD "ingredients" ""
  let instructions := ctx.paramD "instructions" ""
  let prepTime := (ctx.paramD "prepTime" "0").toNat?.getD 0
  let cookTime := (ctx.paramD "cookTime" "0").toNat?.getD 0
  let servings := (ctx.paramD "servings" "4").toNat?.getD 4
  let category := ctx.paramD "category" "Other"
  if title.isEmpty then return ← badRequest "Title is required"
  let now ← recipesGetNowMs
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbRecipe.TxM.setTitle eid title
    DbRecipe.TxM.setDescription eid description
    DbRecipe.TxM.setIngredients eid ingredients
    DbRecipe.TxM.setInstructions eid instructions
    DbRecipe.TxM.setPrepTime eid prepTime
    DbRecipe.TxM.setCookTime eid cookTime
    DbRecipe.TxM.setServings eid servings
    DbRecipe.TxM.setCategory eid category
    DbRecipe.TxM.setUpdatedAt eid now
    audit "UPDATE" "recipe" id [("title", title), ("category", category)]
  let recipeId := id
  let _ ← SSE.publishEvent "recipes" "recipe-updated" (jsonStr! { recipeId, title, category })
  redirect s!"/recipes/{id}"

-- Delete recipe
action recipesDelete "/recipes/:id" DELETE [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let eid : EntityId := ⟨id⟩
  runAuditTx! do
    DbRecipe.TxM.delete eid
    audit "DELETE" "recipe" id []
  let recipeId := id
  let _ ← SSE.publishEvent "recipes" "recipe-deleted" (jsonStr! { recipeId })
  redirect "/recipes"

end HomebaseApp.Pages
