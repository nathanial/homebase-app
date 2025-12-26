/-
  HomebaseApp.Pages.Sections - Simple section pages (unified route + logic + view)

  These are placeholder sections that will be expanded later.
-/
import Scribe
import Loom
import HomebaseApp.Shared

namespace HomebaseApp.Pages

open Scribe
open Loom
open Loom.Page
open Loom.ActionM
open HomebaseApp.Shared

/-! ## Section Content Templates -/

/-- Generic section content -/
def sectionContent (icon title subtitle : String) : HtmlM Unit := do
  div [class_ "bg-white rounded-xl shadow-sm p-8 text-center"] do
    div [class_ "text-6xl mb-4"] (text icon)
    h1 [class_ "text-2xl font-bold text-slate-800 mb-2"] (text title)
    p [class_ "text-slate-500"] (text subtitle)

/-! ## Notebook Section -/

page notebook "/notebook" GET do
  let ctx ← getCtx
  if !isLoggedIn ctx then
    return ← redirect "/login"
  html (Shared.render ctx "Notebook - Homebase" "/notebook"
    (sectionContent "📓" "Notebook" "Notebook section coming soon."))

/-! ## Time Section -/

page time "/time" GET do
  let ctx ← getCtx
  if !isLoggedIn ctx then
    return ← redirect "/login"
  html (Shared.render ctx "Time - Homebase" "/time"
    (sectionContent "⏰" "Time" "Time tracking section coming soon."))

/-! ## Health Section -/

page health "/health" GET do
  let ctx ← getCtx
  if !isLoggedIn ctx then
    return ← redirect "/login"
  html (Shared.render ctx "Health - Homebase" "/health"
    (sectionContent "🏥" "Health" "Health tracking section coming soon."))

/-! ## Recipes Section -/

page recipes "/recipes" GET do
  let ctx ← getCtx
  if !isLoggedIn ctx then
    return ← redirect "/login"
  html (Shared.render ctx "Recipes - Homebase" "/recipes"
    (sectionContent "🍳" "Recipes" "Recipes section coming soon."))

/-! ## Gallery Section -/

page gallery "/gallery" GET do
  let ctx ← getCtx
  if !isLoggedIn ctx then
    return ← redirect "/login"
  html (Shared.render ctx "Gallery - Homebase" "/gallery"
    (sectionContent "🖼️" "Gallery" "Gallery section coming soon."))

/-! ## News Section -/

page news "/news" GET do
  let ctx ← getCtx
  if !isLoggedIn ctx then
    return ← redirect "/login"
  html (Shared.render ctx "News - Homebase" "/news"
    (sectionContent "📰" "News" "News section coming soon."))

end HomebaseApp.Pages
