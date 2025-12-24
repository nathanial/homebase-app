/-
  HomebaseApp.Views.Auth - Authentication views (login, register)

  These pages contain forms and are therefore stable-only.
-/
import Scribe
import Loom
import HomebaseApp.Views.Layout

namespace HomebaseApp.Views.Auth

open Scribe
open Loom
open HomebaseApp.Views.Layout

/-- Login form content (stable - contains form) -/
def loginContent (ctx : Context) : HtmlM .stable Unit := do
  div [class_ "bg-white rounded-xl shadow-lg p-8"] do
    h1 [class_ "text-2xl font-bold text-slate-800 mb-6"] (text "Login")
    form [method_ "post", action_ "/login"] do
      csrfField ctx.csrfToken
      div [class_ "mb-4"] do
        label [for_ "email", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Email")
        input [type_ "email", name_ "email", id_ "email", required_,
               placeholder_ "you@example.com",
               class_ "w-full px-4 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-colors"]
      div [class_ "mb-6"] do
        label [for_ "password", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Password")
        input [type_ "password", name_ "password", id_ "password", required_,
               placeholder_ "Your password",
               class_ "w-full px-4 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-colors"]
      button [type_ "submit", class_ "w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-lg transition-colors"] (text "Login")
    p [class_ "mt-4 text-center text-slate-500"] do
      text "Don't have an account? "
      a [href_ "/register", class_ "text-blue-600 hover:text-blue-700 font-medium"] (text "Register here")

/-- Render login page -/
def renderLogin (ctx : Context) : String :=
  Layout.renderSimple ctx "Login - Homebase" (loginContent ctx)

/-- Register form content (stable - contains form) -/
def registerContent (ctx : Context) : HtmlM .stable Unit := do
  div [class_ "bg-white rounded-xl shadow-lg p-8"] do
    h1 [class_ "text-2xl font-bold text-slate-800 mb-6"] (text "Create Account")
    form [method_ "post", action_ "/register"] do
      csrfField ctx.csrfToken
      div [class_ "mb-4"] do
        label [for_ "name", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Name")
        input [type_ "text", name_ "name", id_ "name", required_,
               placeholder_ "Your name",
               class_ "w-full px-4 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-colors"]
      div [class_ "mb-4"] do
        label [for_ "email", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Email")
        input [type_ "email", name_ "email", id_ "email", required_,
               placeholder_ "you@example.com",
               class_ "w-full px-4 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-colors"]
      div [class_ "mb-6"] do
        label [for_ "password", class_ "block text-sm font-medium text-slate-700 mb-1"] (text "Password")
        input [type_ "password", name_ "password", id_ "password", required_,
               placeholder_ "Choose a password",
               class_ "w-full px-4 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-colors"]
      button [type_ "submit", class_ "w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-lg transition-colors"] (text "Create Account")
    p [class_ "mt-4 text-center text-slate-500"] do
      text "Already have an account? "
      a [href_ "/login", class_ "text-blue-600 hover:text-blue-700 font-medium"] (text "Login here")

/-- Render register page -/
def renderRegister (ctx : Context) : String :=
  Layout.renderSimple ctx "Register - Homebase" (registerContent ctx)

end HomebaseApp.Views.Auth
