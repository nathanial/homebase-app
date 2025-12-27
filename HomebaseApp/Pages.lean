/-
  HomebaseApp.Pages - Imports all pages and generates routes

  This file imports all page definitions and generates:
  - Route type with a constructor for each page
  - registerPages function to bind handlers
-/
import HomebaseApp.Pages.Home
import HomebaseApp.Pages.Auth
import HomebaseApp.Pages.Sections
import HomebaseApp.Pages.Kanban
import HomebaseApp.Pages.Chat
import HomebaseApp.Pages.Admin
import HomebaseApp.Middleware

namespace HomebaseApp.Pages

open Loom.Page
open HomebaseApp.Middleware (authRequired adminRequired)

-- Generate Route type and registerPages function from all pages
#generate_pages

end HomebaseApp.Pages
