/-
  HomebaseApp.Views.Layout - HTML layout wrapper with sidebar navigation
-/
import Scribe
import Loom

namespace HomebaseApp.Views.Layout

open Scribe
open Loom

/-- Render flash messages from context -/
def flashMessages (ctx : Context) : HtmlM Unit := do
  if let some msg := ctx.flash.get "success" then
    div [class_ "flash flash-success"] (text msg)
  if let some msg := ctx.flash.get "error" then
    div [class_ "flash flash-error"] (text msg)
  if let some msg := ctx.flash.get "info" then
    div [class_ "flash flash-info"] (text msg)

/-- Render a sidebar link with active state -/
def sidebarLink (href label currentPath : String) : HtmlM Unit := do
  let activeClass := if currentPath == href then " active" else ""
  a [href_ href, class_ s!"sidebar-link{activeClass}"] (text label)

/-- Sidebar navigation -/
def sidebar (currentPath : String) : HtmlM Unit :=
  aside [class_ "sidebar"] do
    div [class_ "sidebar-header"] (text "Homebase")
    nav [class_ "sidebar-nav"] do
      sidebarLink "/chat" "Chat" currentPath
      sidebarLink "/notebook" "Notebook" currentPath
      sidebarLink "/time" "Time" currentPath
      sidebarLink "/health" "Crohn's Disease" currentPath
      sidebarLink "/recipes" "Recipes" currentPath
      sidebarLink "/kanban" "Kanban" currentPath
      sidebarLink "/gallery" "Gallery" currentPath
      sidebarLink "/news" "News" currentPath

/-- Top navigation bar -/
def navbar (ctx : Context) : HtmlM Unit :=
  nav [class_ "top-nav"] do
    match ctx.session.get "user_name" with
    | some userName =>
      span [class_ "nav-right"] do
        text s!"Hello, {userName} | "
        a [href_ "/logout"] (text "Logout")
    | none =>
      span [class_ "nav-right"] do
        a [href_ "/login"] (text "Login")
        text " "
        a [href_ "/register"] (text "Register")

/-- Main layout wrapper with sidebar -/
def layout (ctx : Context) (pageTitle : String) (currentPath : String) (content : HtmlM Unit) : Html :=
  HtmlM.build do
    raw "<!DOCTYPE html>"
    html [lang_ "en"] do
      head [] do
        meta_ [charset_ "utf-8"]
        meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
        title pageTitle
        raw "<link rel=\"stylesheet\" href=\"/styles.css\">"
      body [] do
        div [class_ "app-container"] do
          sidebar currentPath
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
        raw "<link rel=\"stylesheet\" href=\"/styles.css\">"
      body [] do
        div [class_ "simple-container"] do
          flashMessages ctx
          content
  html.render

end HomebaseApp.Views.Layout
