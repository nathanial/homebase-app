/-
  HomebaseApp.Views.Layout - HTML layout wrapper with sidebar navigation
-/
import Scribe
import Loom
import HomebaseApp.Routes
import HomebaseApp.Helpers

namespace HomebaseApp.Views.Layout

open Scribe
open Loom
open HomebaseApp (Route)
open HomebaseApp.Helpers (isAdmin)

/-- Render flash messages from context -/
def flashMessages (ctx : Context) : HtmlM Unit := do
  if let some msg := ctx.flash.get "success" then
    div [class_ "flash flash-success"] (text msg)
  if let some msg := ctx.flash.get "error" then
    div [class_ "flash flash-error"] (text msg)
  if let some msg := ctx.flash.get "info" then
    div [class_ "flash flash-info"] (text msg)

/-- Render a sidebar link with active state and icon -/
def sidebarLink (href icon label currentPath : String) : HtmlM Unit := do
  let activeClass := if currentPath == href then " active" else ""
  a [href_ href, class_ s!"sidebar-link{activeClass}"] do
    span [class_ "sidebar-link-icon"] (text icon)
    span [] (text label)

/-- Sidebar navigation -/
def sidebar (ctx : Context) (currentPath : String) : HtmlM Unit :=
  aside [class_ "sidebar"] do
    div [class_ "sidebar-header"] do
      span [class_ "sidebar-header-icon"] (text "🏠")
      text "Homebase"
    nav [class_ "sidebar-nav"] do
      sidebarLink "/chat" "💬" "Chat" currentPath
      sidebarLink "/notebook" "📓" "Notebook" currentPath
      sidebarLink "/time" "⏰" "Time" currentPath
      sidebarLink "/health" "🏥" "Health" currentPath
      sidebarLink "/recipes" "🍳" "Recipes" currentPath
      sidebarLink "/kanban" "📋" "Kanban" currentPath
      sidebarLink "/gallery" "🖼️" "Gallery" currentPath
      sidebarLink "/news" "📰" "News" currentPath
      -- Admin link (only visible to admins)
      if isAdmin ctx then
        div [class_ "sidebar-divider"] (pure ())
        sidebarLink "/admin" "⚙️" "Admin" currentPath

/-- Top navigation bar -/
def navbar (ctx : Context) : HtmlM Unit :=
  nav [class_ "navbar"] do
    match ctx.session.get "user_name" with
    | some userName =>
      div [class_ "navbar-user"] do
        span [class_ "navbar-username"] (text s!"Hello, {userName}")
        a [href_ "/logout", class_ "navbar-link"] (text "Logout")
    | none =>
      div [class_ "navbar-user"] do
        a [href_ "/login", class_ "navbar-link"] (text "Login")
        a [href_ "/register", class_ "navbar-link navbar-link-primary"] (text "Register")

/-- Main layout wrapper with sidebar -/
def layout (ctx : Context) (pageTitle : String) (currentPath : String) (content : HtmlM Unit) : Html :=
  HtmlM.build do
    raw "<!DOCTYPE html>"
    html [lang_ "en"] do
      head [] do
        meta_ [charset_ "utf-8"]
        meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
        title pageTitle
        link [rel_ "stylesheet", href' (Route.staticCss "app.css")]
      body [] do
        div [class_ "app-container"] do
          sidebar ctx currentPath
          div [class_ "main-area"] do
            navbar ctx
            div [class_ "main-content"] do
              flashMessages ctx
              content

/-- Render layout to string -/
def render (ctx : Context) (pageTitle : String) (currentPath : String) (content : HtmlM Unit) : String :=
  (layout ctx pageTitle currentPath content).render

/-- Render layout without sidebar (for auth pages) -/
def renderSimple (ctx : Context) (pageTitle : String) (content : HtmlM Unit) : String :=
  let html := HtmlM.build do
    raw "<!DOCTYPE html>"
    html [lang_ "en"] do
      head [] do
        meta_ [charset_ "utf-8"]
        meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
        title pageTitle
        link [rel_ "stylesheet", href' (Route.staticCss "app.css")]
      body [class_ "auth-container"] do
        div [class_ "auth-box"] do
          flashMessages ctx
          content
  html.render

end HomebaseApp.Views.Layout
