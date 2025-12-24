/-
  HomebaseApp.Views.Layout - HTML layout wrapper with sidebar navigation (Tailwind CSS)
-/
import Scribe
import Loom

namespace HomebaseApp.Views.Layout

open Scribe
open Loom

/-- Render flash messages from context -/
def flashMessages (ctx : Context) : HtmlM Unit := do
  if let some msg := ctx.flash.get "success" then
    div [class_ "mb-4 p-4 rounded-lg bg-green-100 text-green-800 border border-green-200"] (text msg)
  if let some msg := ctx.flash.get "error" then
    div [class_ "mb-4 p-4 rounded-lg bg-red-100 text-red-800 border border-red-200"] (text msg)
  if let some msg := ctx.flash.get "info" then
    div [class_ "mb-4 p-4 rounded-lg bg-blue-100 text-blue-800 border border-blue-200"] (text msg)

/-- Render a sidebar link with active state -/
def sidebarLink (href label currentPath : String) : HtmlM Unit := do
  let baseClass := "block px-6 py-3 text-slate-300 hover:bg-slate-700 hover:text-white transition-colors"
  let activeClass := if currentPath == href then " bg-blue-600 text-white" else ""
  a [href_ href, class_ s!"{baseClass}{activeClass}"] (text label)

/-- Sidebar navigation -/
def sidebar (currentPath : String) : HtmlM Unit :=
  aside [class_ "w-56 bg-slate-800 text-white flex-shrink-0"] do
    div [class_ "p-5 text-xl font-bold border-b border-slate-700"] (text "Homebase")
    nav [class_ "py-4"] do
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
  nav [class_ "bg-slate-900 text-white px-6 py-4 flex justify-end"] do
    match ctx.session.get "user_name" with
    | some userName =>
      div [class_ "flex items-center gap-4"] do
        span [class_ "text-slate-300"] (text s!"Hello, {userName}")
        a [href_ "/logout", class_ "text-slate-300 hover:text-white transition-colors"] (text "Logout")
    | none =>
      div [class_ "flex items-center gap-4"] do
        a [href_ "/login", class_ "text-slate-300 hover:text-white transition-colors"] (text "Login")
        a [href_ "/register", class_ "bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded-lg transition-colors"] (text "Register")

/-- Main layout wrapper with sidebar -/
def layout (ctx : Context) (pageTitle : String) (currentPath : String) (content : HtmlM Unit) : Html :=
  HtmlM.build do
    raw "<!DOCTYPE html>"
    html [lang_ "en"] do
      head [] do
        meta_ [charset_ "utf-8"]
        meta_ [name_ "viewport", content_ "width=device-width, initial-scale=1"]
        title pageTitle
        raw "<script src=\"https://cdn.tailwindcss.com\"></script>"
      body [class_ "bg-slate-100 text-slate-900"] do
        div [class_ "flex min-h-screen"] do
          sidebar currentPath
          div [class_ "flex-1 flex flex-col"] do
            navbar ctx
            div [class_ "flex-1 p-6"] do
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
        raw "<script src=\"https://cdn.tailwindcss.com\"></script>"
      body [class_ "bg-slate-100 text-slate-900 min-h-screen flex items-center justify-center"] do
        div [class_ "w-full max-w-md p-6"] do
          flashMessages ctx
          content
  html.render

end HomebaseApp.Views.Layout
