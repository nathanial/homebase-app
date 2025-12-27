/-
  HomebaseApp.Middleware - Application-specific route middleware
-/
import Loom

namespace HomebaseApp.Middleware

open Loom

/-- Check if a user is logged in (has user_id in session) -/
def isLoggedIn (ctx : Context) : Bool :=
  ctx.session.has "user_id"

/-- Check if user is admin (is_admin = "true" in session) -/
def isAdmin (ctx : Context) : Bool :=
  ctx.session.get "is_admin" == some "true"

/-- Middleware that requires authentication, redirects to /login if not logged in -/
def authRequired : RouteMiddleware :=
  RouteMiddleware.guard isLoggedIn "/login" "error" "Please log in to continue"

/-- Middleware that requires admin privileges -/
def adminRequired : RouteMiddleware :=
  RouteMiddleware.guard isAdmin "/" "error" "Access denied. Admin privileges required."

end HomebaseApp.Middleware
