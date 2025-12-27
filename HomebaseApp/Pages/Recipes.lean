/-
  HomebaseApp.Pages.Recipes - Recipe storage with ingredients and instructions
-/
import Scribe
import Loom
import Loom.SSE
import Ledger
import HomebaseApp.Shared
import HomebaseApp.Models
import HomebaseApp.Entities
import HomebaseApp.Helpers
import HomebaseApp.Middleware

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

/-! ## Helpers -/

/-- Get current time in milliseconds -/
def recipesGetNowMs : IO Nat := do
  let output ← IO.Process.output { cmd := "date", args := #["+%s"] }
  let seconds := output.stdout.trim.toNat?.getD 0
  return seconds * 1000

/-- Format time in minutes -/
def recipesFormatTime (minutes : Nat) : String :=
  if minutes >= 60 then
    let hours := minutes / 60
    let mins := minutes % 60
    if mins > 0 then s!"{hours}h {mins}m" else s!"{hours}h"
  else if minutes > 0 then s!"{minutes}m"
  else "—"

/-- Get total cooking time -/
def recipesTotalTime (prepTime cookTime : Nat) : Nat :=
  prepTime + cookTime

/-- Get current user's EntityId -/
def recipesGetCurrentUserEid (ctx : Context) : Option EntityId :=
  match currentUserId ctx with
  | some idStr => idStr.toNat?.map fun n => ⟨n⟩
  | none => none

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

/-! ## View Helpers -/

/-- Attribute to clear modal after form submission -/
def recipesModalClearAttr : Attr :=
  ⟨"hx-on::after-request", "document.getElementById('modal-container').innerHTML = ''"⟩

/-- Get active class for filter tab -/
def recipesFilterClass (currentFilter target : String) : String :=
  if currentFilter == target then "recipes-filter-tab active" else "recipes-filter-tab"

/-- Render category filter tabs -/
def recipesRenderFilterTabs (currentFilter : String) : HtmlM Unit := do
  div [class_ "recipes-filters"] do
    a [href_ "/recipes", class_ (recipesFilterClass currentFilter "all")] (text "All")
    for cat in recipeCategories do
      a [href_ s!"/recipes?category={cat}", class_ (recipesFilterClass currentFilter cat)] do
        span [] (text (recipesCategoryIcon cat))
        text s!" {cat}"

/-- Render a single recipe card -/
def recipesRenderCard (recipe : RecipeView) : HtmlM Unit := do
  a [href_ s!"/recipes/{recipe.id}", class_ "recipes-card"] do
    div [class_ "recipes-card-header"] do
      span [class_ "recipes-card-icon"] (text (recipesCategoryIcon recipe.category))
      span [class_ "recipes-card-category"] (text recipe.category)
    h3 [class_ "recipes-card-title"] (text recipe.title)
    if !recipe.description.isEmpty then
      p [class_ "recipes-card-description"] (text (recipe.description.take 100))
    div [class_ "recipes-card-meta"] do
      if recipe.prepTime > 0 || recipe.cookTime > 0 then
        span [class_ "recipes-card-time"] do
          text "⏱️ "
          text (recipesFormatTime (recipesTotalTime recipe.prepTime recipe.cookTime))
      if recipe.servings > 0 then
        span [class_ "recipes-card-servings"] do
          text "👥 "
          text (toString recipe.servings)

/-- Render recipe grid -/
def recipesRenderGrid (recipes : List RecipeView) : HtmlM Unit := do
  if recipes.isEmpty then
    div [class_ "recipes-empty"] do
      div [class_ "recipes-empty-icon"] (text "🍳")
      p [] (text "No recipes yet")
      p [class_ "text-muted"] (text "Add your first recipe!")
  else
    div [class_ "recipes-grid"] do
      for recipe in recipes do recipesRenderCard recipe

/-- Parse ingredients string to list -/
def recipesParseIngredients (ingredients : String) : List String :=
  ingredients.splitOn "\n" |>.filter (!·.isEmpty)

/-- Render recipe detail view -/
def recipesRenderDetail (recipe : RecipeView) (ctx : Context) : HtmlM Unit := do
  div [class_ "recipes-detail"] do
    -- Header
    div [class_ "recipes-detail-header"] do
      a [href_ "/recipes", class_ "btn btn-secondary btn-sm"] (text "Back")
      div [class_ "recipes-detail-actions"] do
        a [href_ s!"/recipes/{recipe.id}/edit", class_ "btn btn-secondary btn-sm"] (text "Edit")
        button [hx_delete s!"/recipes/{recipe.id}", hx_swap "none",
                hx_confirm "Delete this recipe?", class_ "btn btn-danger btn-sm"] (text "Delete")
    -- Title and category
    div [class_ "recipes-detail-title-section"] do
      span [class_ "recipes-detail-icon"] (text (recipesCategoryIcon recipe.category))
      div [] do
        h1 [] (text recipe.title)
        span [class_ "recipes-detail-category"] (text recipe.category)
    -- Description
    if !recipe.description.isEmpty then
      p [class_ "recipes-detail-description"] (text recipe.description)
    -- Meta info
    div [class_ "recipes-detail-meta"] do
      if recipe.prepTime > 0 then
        div [class_ "recipes-detail-meta-item"] do
          span [class_ "recipes-detail-meta-label"] (text "Prep Time")
          span [class_ "recipes-detail-meta-value"] (text (recipesFormatTime recipe.prepTime))
      if recipe.cookTime > 0 then
        div [class_ "recipes-detail-meta-item"] do
          span [class_ "recipes-detail-meta-label"] (text "Cook Time")
          span [class_ "recipes-detail-meta-value"] (text (recipesFormatTime recipe.cookTime))
      if recipe.prepTime > 0 || recipe.cookTime > 0 then
        div [class_ "recipes-detail-meta-item"] do
          span [class_ "recipes-detail-meta-label"] (text "Total Time")
          span [class_ "recipes-detail-meta-value"] (text (recipesFormatTime (recipesTotalTime recipe.prepTime recipe.cookTime)))
      if recipe.servings > 0 then
        div [class_ "recipes-detail-meta-item"] do
          span [class_ "recipes-detail-meta-label"] (text "Servings")
          span [class_ "recipes-detail-meta-value"] (text (toString recipe.servings))
    -- Content sections
    div [class_ "recipes-detail-content"] do
      -- Ingredients
      div [class_ "recipes-detail-section"] do
        h2 [] (text "Ingredients")
        let ingredientsList := recipesParseIngredients recipe.ingredients
        if ingredientsList.isEmpty then
          p [class_ "text-muted"] (text "No ingredients listed")
        else
          ul [class_ "recipes-ingredients-list"] do
            for ingredient in ingredientsList do
              li [] (text ingredient)
      -- Instructions
      div [class_ "recipes-detail-section"] do
        h2 [] (text "Instructions")
        if recipe.instructions.isEmpty then
          p [class_ "text-muted"] (text "No instructions provided")
        else
          div [class_ "recipes-instructions"] do
            -- Simple rendering: each line is a step
            let steps := recipe.instructions.splitOn "\n" |>.filter (!·.isEmpty)
            ol [class_ "recipes-steps-list"] do
              for step in steps do
                li [] (text step)

/-- Main recipes page content -/
def recipesPageContent (ctx : Context) (recipes : List RecipeView) (filter : String) : HtmlM Unit := do
  div [class_ "recipes-container"] do
    -- Header
    div [class_ "recipes-header"] do
      h1 [] (text "Recipes")
      a [href_ "/recipes/new", class_ "btn btn-primary"] (text "+ New Recipe")
    -- Filters
    recipesRenderFilterTabs filter
    -- Grid
    div [id_ "recipes-grid"] do
      recipesRenderGrid recipes
    -- Modal container
    div [id_ "modal-container"] (pure ())
    -- SSE script
    script [src_ "/js/recipes.js"]

/-! ## Pages -/

-- Main recipes page
view recipesPage "/recipes" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  let filter := ctx.paramD "category" "all"
  let recipes := if filter == "all" then getRecipes ctx else getRecipesByCategory ctx filter
  html (Shared.render ctx "Recipes - Homebase" "/recipes"
    (recipesPageContent ctx recipes filter))

-- View single recipe
view recipeView "/recipes/:id" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getRecipe ctx id with
  | none => notFound "Recipe not found"
  | some recipe =>
    html (Shared.render ctx s!"{recipe.title} - Recipes" "/recipes"
      (recipesRenderDetail recipe ctx))

-- New recipe form
view recipesNewForm "/recipes/new" [HomebaseApp.Middleware.authRequired] do
  let ctx ← getCtx
  html (Shared.render ctx "New Recipe - Recipes" "/recipes" do
    div [class_ "recipes-form-container"] do
      div [class_ "recipes-form-header"] do
        a [href_ "/recipes", class_ "btn btn-secondary btn-sm"] (text "Cancel")
        h1 [] (text "New Recipe")
      form [action_ "/recipes/create", method_ "POST", class_ "recipes-form"] do
        csrfField ctx.csrfToken
        div [class_ "form-row"] do
          div [class_ "form-group form-group-wide"] do
            label [for_ "title", class_ "form-label"] (text "Title")
            input [type_ "text", name_ "title", id_ "title", class_ "form-input", required_]
          div [class_ "form-group"] do
            label [for_ "category", class_ "form-label"] (text "Category")
            select [name_ "category", id_ "category", class_ "form-select"] do
              for cat in recipeCategories do
                option [value_ cat] cat
        div [class_ "form-group"] do
          label [for_ "description", class_ "form-label"] (text "Description")
          textarea [name_ "description", id_ "description", class_ "form-textarea", rows_ 2,
                    placeholder_ "Brief description of the dish..."] ""
        div [class_ "form-row"] do
          div [class_ "form-group"] do
            label [for_ "prepTime", class_ "form-label"] (text "Prep Time (minutes)")
            input [type_ "number", name_ "prepTime", id_ "prepTime", class_ "form-input",
                   value_ "0", attr_ "min" "0"]
          div [class_ "form-group"] do
            label [for_ "cookTime", class_ "form-label"] (text "Cook Time (minutes)")
            input [type_ "number", name_ "cookTime", id_ "cookTime", class_ "form-input",
                   value_ "0", attr_ "min" "0"]
          div [class_ "form-group"] do
            label [for_ "servings", class_ "form-label"] (text "Servings")
            input [type_ "number", name_ "servings", id_ "servings", class_ "form-input",
                   value_ "4", attr_ "min" "1"]
        div [class_ "form-group"] do
          label [for_ "ingredients", class_ "form-label"] (text "Ingredients (one per line)")
          textarea [name_ "ingredients", id_ "ingredients", class_ "form-textarea", rows_ 8,
                    placeholder_ "1 cup flour\n2 eggs\n1/2 cup sugar\n..."] ""
        div [class_ "form-group"] do
          label [for_ "instructions", class_ "form-label"] (text "Instructions (one step per line)")
          textarea [name_ "instructions", id_ "instructions", class_ "form-textarea", rows_ 10,
                    placeholder_ "Preheat oven to 350°F\nMix dry ingredients\nAdd wet ingredients\n..."] ""
        div [class_ "form-actions"] do
          a [href_ "/recipes", class_ "btn btn-secondary"] (text "Cancel")
          button [type_ "submit", class_ "btn btn-primary"] (text "Create Recipe"))

-- Edit recipe form
view recipesEditForm "/recipes/:id/edit" [HomebaseApp.Middleware.authRequired] (id : Nat) do
  let ctx ← getCtx
  match getRecipe ctx id with
  | none => notFound "Recipe not found"
  | some recipe =>
    html (Shared.render ctx s!"Edit {recipe.title} - Recipes" "/recipes" do
      div [class_ "recipes-form-container"] do
        div [class_ "recipes-form-header"] do
          a [href_ s!"/recipes/{id}", class_ "btn btn-secondary btn-sm"] (text "Cancel")
          h1 [] (text "Edit Recipe")
        form [action_ s!"/recipes/{id}", method_ "POST", class_ "recipes-form"] do
          input [type_ "hidden", name_ "_method", value_ "PUT"]
          csrfField ctx.csrfToken
          div [class_ "form-row"] do
            div [class_ "form-group form-group-wide"] do
              label [for_ "title", class_ "form-label"] (text "Title")
              input [type_ "text", name_ "title", id_ "title", class_ "form-input",
                     value_ recipe.title, required_]
            div [class_ "form-group"] do
              label [for_ "category", class_ "form-label"] (text "Category")
              select [name_ "category", id_ "category", class_ "form-select"] do
                for cat in recipeCategories do
                  if cat == recipe.category then
                    option [value_ cat, selected_] cat
                  else
                    option [value_ cat] cat
          div [class_ "form-group"] do
            label [for_ "description", class_ "form-label"] (text "Description")
            textarea [name_ "description", id_ "description", class_ "form-textarea", rows_ 2] recipe.description
          div [class_ "form-row"] do
            div [class_ "form-group"] do
              label [for_ "prepTime", class_ "form-label"] (text "Prep Time (minutes)")
              input [type_ "number", name_ "prepTime", id_ "prepTime", class_ "form-input",
                     value_ (toString recipe.prepTime), attr_ "min" "0"]
            div [class_ "form-group"] do
              label [for_ "cookTime", class_ "form-label"] (text "Cook Time (minutes)")
              input [type_ "number", name_ "cookTime", id_ "cookTime", class_ "form-input",
                     value_ (toString recipe.cookTime), attr_ "min" "0"]
            div [class_ "form-group"] do
              label [for_ "servings", class_ "form-label"] (text "Servings")
              input [type_ "number", name_ "servings", id_ "servings", class_ "form-input",
                     value_ (toString recipe.servings), attr_ "min" "1"]
          div [class_ "form-group"] do
            label [for_ "ingredients", class_ "form-label"] (text "Ingredients (one per line)")
            textarea [name_ "ingredients", id_ "ingredients", class_ "form-textarea", rows_ 8] recipe.ingredients
          div [class_ "form-group"] do
            label [for_ "instructions", class_ "form-label"] (text "Instructions (one step per line)")
            textarea [name_ "instructions", id_ "instructions", class_ "form-textarea", rows_ 10] recipe.instructions
          div [class_ "form-actions"] do
            a [href_ s!"/recipes/{id}", class_ "btn btn-secondary"] (text "Cancel")
            button [type_ "submit", class_ "btn btn-primary"] (text "Save Changes"))

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
