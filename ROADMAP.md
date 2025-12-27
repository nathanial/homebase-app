# Homebase App Roadmap

This document outlines feature opportunities, code improvements, and cleanup tasks for the Homebase personal dashboard application.

## Table of Contents

- [Feature Proposals](#feature-proposals)
- [Code Improvements](#code-improvements)
- [Code Cleanup](#code-cleanup)
- [Security Considerations](#security-considerations)
- [Performance Improvements](#performance-improvements)
- [UX/UI Improvements](#uxui-improvements)

---

## Feature Proposals

### [Priority: High] Implement Placeholder Dashboard Sections

**Description:** Six dashboard sections (Notebook, Time, Health, Recipes, Gallery, News) are currently placeholder pages displaying "coming soon" messages.

**Rationale:** These sections are prominently featured in the sidebar navigation, but clicking them leads to empty content. Implementing at least basic functionality for these sections would significantly improve the application's utility.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Sections.lean`
- New files for each section (e.g., `Notebook.lean`, `Time.lean`, etc.)
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Models.lean` (new entity definitions)

**Suggested Implementations:**
- **Notebook:** Markdown-based notes with folders/tags
- **Time:** Time tracking with timers and daily/weekly reports
- **Health:** Weight, exercise, medication tracking
- **Recipes:** Recipe storage with ingredients and instructions
- **Gallery:** Photo/file gallery leveraging existing upload infrastructure
- **News:** RSS feed reader or link aggregator

**Estimated Effort:** Large (per section: Medium)
**Dependencies:** None

---

### [Priority: High] Password Reset and Email Verification

**Description:** The authentication system lacks password reset functionality and email verification for new accounts.

**Rationale:** Users cannot recover access if they forget their password. Email verification would prevent account creation with fake emails.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Auth.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Models.lean`
- New email sending infrastructure

**Estimated Effort:** Large
**Dependencies:** Email sending capability (would require SMTP integration or external service)

---

### [Priority: High] User Profile and Settings Page

**Description:** Users have no way to view or update their own profile information (name, password) after registration.

**Rationale:** Standard feature for any user-authenticated application. Currently only admins can modify user data.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/` (new `Profile.lean` file)
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Shared.lean` (add profile link to navbar)

**Estimated Effort:** Medium
**Dependencies:** None

---

### [Priority: Medium] Kanban Board Sharing and Collaboration

**Description:** Kanban boards are currently accessible to all authenticated users with no ownership or permission model.

**Rationale:** For a personal dashboard, users may want private boards. For team use, explicit sharing would be valuable.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Models.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean`

**Estimated Effort:** Large
**Dependencies:** User profile system

---

### [Priority: Medium] Chat Thread Participants and Mentions

**Description:** Chat threads have no concept of participants or user mentions.

**Rationale:** For multi-user scenarios, knowing who is in a conversation and being able to @mention users would improve communication.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Models.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Chat.lean`

**Estimated Effort:** Medium
**Dependencies:** None

---

### [Priority: Medium] Kanban Card Due Dates and Reminders

**Description:** Kanban cards lack due dates, start dates, or any time-based attributes.

**Rationale:** Due dates are a fundamental feature for task management boards.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Models.lean` (add `dueDate` to `DbCard`)
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean` (card forms and display)
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/css/kanban.css`

**Estimated Effort:** Medium
**Dependencies:** None

---

### [Priority: Medium] Kanban Card Checklists

**Description:** Cards cannot contain subtasks or checklists.

**Rationale:** Checklists are valuable for breaking down cards into smaller actionable items.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Models.lean` (new `DbCardChecklist` entity)
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean`

**Estimated Effort:** Medium
**Dependencies:** None

---

### [Priority: Medium] Kanban Card Comments

**Description:** Cards have no comment/discussion functionality.

**Rationale:** Comments allow for conversation and context around tasks.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Models.lean` (new `DbCardComment` entity)
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean`

**Estimated Effort:** Medium
**Dependencies:** None

---

### [Priority: Low] Dark Mode Theme

**Description:** The application only supports a light theme.

**Rationale:** Many users prefer dark mode, especially for extended use.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/css/app.css`
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/css/kanban.css`
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/css/chat.css`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Shared.lean` (add theme toggle)

**Estimated Effort:** Medium
**Dependencies:** User profile/settings page (to persist preference)

---

### [Priority: Low] Kanban Card Attachments

**Description:** Cards cannot have file attachments (unlike chat messages).

**Rationale:** Attaching files to tasks is useful for documentation and reference.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Models.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean`
- Reuse existing upload infrastructure from Chat

**Estimated Effort:** Medium
**Dependencies:** None

---

### [Priority: Low] Activity/Audit Log UI

**Description:** While audit logging exists in the backend, there's no UI to view activity history.

**Rationale:** Users and admins may want to see who changed what and when.

**Affected Files:**
- New page in `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/`
- May need to query Chronicle logs or add a separate audit trail entity

**Estimated Effort:** Medium
**Dependencies:** None

---

### [Priority: Low] Keyboard Shortcuts

**Description:** No keyboard shortcuts for common actions.

**Rationale:** Power users benefit from keyboard navigation (e.g., `n` for new card, `?` for help).

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/js/kanban.js`
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/js/chat.js`

**Estimated Effort:** Small
**Dependencies:** None

---

## Code Improvements

### [Priority: High] Consolidate Duplicate Password Hashing Implementation

**Current State:** Password hashing is implemented twice - once in `Helpers.lean` (lines 17-38) and again in `Auth.lean` (lines 22-36) with identical logic.

**Proposed Change:** Remove the duplicate implementation in `Auth.lean` and import from `Helpers.lean`. The comment "copied from Helpers to avoid circular deps" suggests a past issue, but the current import structure should allow this.

**Benefits:** Single source of truth, easier maintenance, reduced code duplication.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Auth.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Helpers.lean`

**Estimated Effort:** Small

---

### [Priority: High] Consolidate Duplicate isLoggedIn and isAdmin Implementations

**Current State:** These helper functions are defined in three places:
1. `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Helpers.lean` (lines 59-77)
2. `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Shared.lean` (lines 18-25)
3. `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Middleware.lean` (lines 11-16)

The implementations differ slightly (`Shared.lean` checks session for `is_admin`, while `Helpers.lean` queries the database).

**Proposed Change:** Consolidate to a single implementation with consistent behavior. The database-based check in `Helpers.lean` is more secure (reflects current DB state).

**Benefits:** Consistent behavior, reduced maintenance burden, clearer code.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Helpers.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Shared.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Middleware.lean`

**Estimated Effort:** Small

---

### [Priority: High] Standardize Route Authentication Pattern

**Current State:** Some pages check authentication manually (`if !isLoggedIn ctx then return <- redirect "/login"`) while others use middleware (`[HomebaseApp.Middleware.authRequired]`).

**Proposed Change:** Consistently use the middleware pattern for all protected routes, removing inline authentication checks.

**Benefits:** Cleaner code, consistent behavior, easier to add features like "remember me" later.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Home.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Sections.lean`

**Estimated Effort:** Small

---

### [Priority: Medium] Add Database Error Handling

**Current State:** Many database operations use pattern matching on `ctx.database` returning empty lists or `none` for errors, with no user feedback.

**Proposed Change:** Add proper error handling and user-facing error messages when the database is unavailable.

**Benefits:** Better user experience, easier debugging.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Chat.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Admin.lean`

**Estimated Effort:** Medium

---

### [Priority: Medium] Extract View Rendering to Separate Module

**Current State:** View rendering functions (e.g., `renderCard`, `renderColumn`, `renderMessage`) are mixed with database queries and action handlers in page files.

**Proposed Change:** Create separate view modules (e.g., `Views/Kanban.lean`, `Views/Chat.lean`) for HTML rendering logic.

**Benefits:** Better separation of concerns, easier testing, smaller file sizes.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Chat.lean`
- New `Views/` directory

**Estimated Effort:** Medium

---

### [Priority: Medium] Type-Safe Route Parameters

**Current State:** Route parameters are parsed from strings manually (e.g., `ctx.paramD "column_id" ""` then `columnIdStr.toNat?`).

**Proposed Change:** Use the page macro's parameter type declarations consistently and add better validation.

**Benefits:** Compile-time safety where possible, consistent error handling.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Chat.lean`

**Estimated Effort:** Medium

---

### [Priority: Low] Add Request Rate Limiting

**Current State:** No rate limiting on any endpoints.

**Proposed Change:** Add middleware-based rate limiting for login attempts and form submissions.

**Benefits:** Protection against brute-force attacks and abuse.

**Affected Files:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Middleware.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Main.lean`

**Estimated Effort:** Medium
**Dependencies:** May require Loom framework changes

---

## Code Cleanup

### [Priority: High] Remove Unused Legacy Backward Compatibility Code

**Issue:** The Kanban module contains legacy code for backward compatibility (e.g., `boardContent` function, `kanbanAddColumnForm`, `kanbanCreateColumn` routes).

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean` (lines 271-286, 468-503)

**Action Required:** Verify if legacy routes are still needed. If not, remove them to reduce code size.

**Estimated Effort:** Small

---

### [Priority: Medium] Consolidate Database Helper Patterns

**Issue:** Similar helper functions exist for each entity type with slightly different patterns. For example, `getBoard`, `getColumn`, `getCard` in Kanban, and `getChatThread`, `getMessagesForThread` in Chat.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean` (lines 54-157)
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Chat.lean` (lines 66-131)

**Action Required:** Consider creating a generic pattern or extracting to a shared module.

**Estimated Effort:** Medium

---

### [Priority: Medium] Remove Inline JavaScript Event Handlers

**Issue:** Several places use inline JavaScript in HTML attributes (e.g., `attr_ "onclick"`, `attr_ "ondragover"`).

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean` (modal close handlers)
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Chat.lean` (upload zone handlers)

**Action Required:** Move event handlers to JavaScript files for better separation and CSP compliance.

**Estimated Effort:** Small

---

### [Priority: Low] Add Missing Test Coverage

**Issue:** Only Kanban card operations have tests. No tests for:
- Authentication flows
- Chat operations
- Admin operations
- Upload functionality

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Tests/`

**Action Required:** Add test suites for each major feature area.

**Estimated Effort:** Large

---

### [Priority: Low] Improve Code Documentation

**Issue:** While the code has some doc comments, many functions lack documentation, especially in the larger files.

**Location:** All source files

**Action Required:** Add doc comments to public functions explaining purpose, parameters, and return values.

**Estimated Effort:** Medium

---

## Security Considerations

### [Priority: Critical] Replace Weak Password Hashing Algorithm

**Issue:** The application uses a simple polynomial hash for passwords (see `Helpers.lean` lines 17-34). This is explicitly marked as "demo only" but should not be used in any production scenario.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Helpers.lean` (lines 17-34)
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Auth.lean` (lines 22-36)

**Action Required:** Replace with bcrypt, argon2, or similar secure password hashing. This would require FFI bindings to a cryptographic library.

**Estimated Effort:** Medium
**Dependencies:** Cryptographic library FFI

---

### [Priority: High] Enable CSRF Protection

**Issue:** CSRF protection is explicitly disabled in the configuration (`csrfEnabled := false` in `Main.lean` line 22).

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Main.lean` (line 22)

**Action Required:** Enable CSRF protection. The CSRF token field is already present in forms (`csrfField ctx.csrfToken`), so enabling should work.

**Estimated Effort:** Small

---

### [Priority: High] Secure Session Secret Key

**Issue:** The session secret key is hardcoded in source code (`secretKey := "homebase-app-secret-key-min-32-chars!!".toUTF8` in `Main.lean` line 19).

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Main.lean` (line 19)

**Action Required:** Load secret key from environment variable or secure configuration file.

**Estimated Effort:** Small

---

### [Priority: Medium] Add Input Validation for Form Fields

**Issue:** Limited validation on form inputs. For example, email format is not validated server-side, password strength is not enforced.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Auth.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Admin.lean`

**Action Required:** Add server-side validation for email format, password strength, and other user inputs.

**Estimated Effort:** Medium

---

### [Priority: Medium] Add Session Timeout

**Issue:** Sessions appear to have no expiration. Users stay logged in indefinitely.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Main.lean`

**Action Required:** Configure session expiration and implement session renewal on activity.

**Estimated Effort:** Small
**Dependencies:** May require Loom framework changes

---

### [Priority: Low] Add Content Security Policy Headers

**Issue:** While security headers middleware exists, CSP headers are not configured.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Middleware.lean`

**Action Required:** Add appropriate CSP headers, though this may require changes to inline scripts.

**Estimated Effort:** Medium

---

## Performance Improvements

### [Priority: Medium] Add Database Query Pagination

**Issue:** All list queries (boards, columns, cards, threads, messages) load all results without pagination.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Kanban.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Chat.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Admin.lean`

**Action Required:** Add pagination for admin user list, chat messages, and potentially large card lists.

**Estimated Effort:** Medium

---

### [Priority: Medium] Optimize SSE Event Broadcasting

**Issue:** SSE events trigger full section reloads even when partial updates would suffice.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/js/kanban.js` (lines 82-96)
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/js/chat.js` (lines 213-231)

**Action Required:** Use SSE event data to perform targeted DOM updates instead of full HTMX reloads.

**Estimated Effort:** Medium

---

### [Priority: Low] Add Static Asset Caching Headers

**Issue:** CSS and JS files are served without explicit cache headers (only uploads have caching).

**Location:**
- Static file serving (likely in Loom framework)

**Action Required:** Configure appropriate cache headers for static assets.

**Estimated Effort:** Small

---

### [Priority: Low] Bundle and Minify JavaScript

**Issue:** JavaScript files are served as-is without minification or bundling.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/js/`

**Action Required:** Add build step to bundle and minify JS (consider esbuild or similar).

**Estimated Effort:** Small

---

## UX/UI Improvements

### [Priority: High] Add Loading States and Feedback

**Issue:** HTMX operations show no loading indicators. Users don't know if an action is processing.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/css/app.css`
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/js/kanban.js`
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/js/chat.js`

**Action Required:** Add loading spinners, button disable states, and skeleton loaders.

**Estimated Effort:** Medium

---

### [Priority: Medium] Improve Mobile Responsiveness

**Issue:** The sidebar-based layout may not work well on mobile devices.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/css/app.css`
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/css/kanban.css`
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/css/chat.css`

**Action Required:** Add responsive breakpoints for tablet and mobile layouts, consider collapsible sidebar.

**Estimated Effort:** Medium

---

### [Priority: Medium] Add Toast Notifications

**Issue:** Flash messages only appear on page load/redirect. HTMX operations don't show feedback.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Shared.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/js/` (new file)

**Action Required:** Add a toast notification system for real-time feedback.

**Estimated Effort:** Medium

---

### [Priority: Medium] Improve Form Validation UX

**Issue:** Form errors redirect to the same page with flash messages. No inline validation.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Auth.lean`
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Pages/Admin.lean`

**Action Required:** Add client-side validation and inline error messages.

**Estimated Effort:** Medium

---

### [Priority: Low] Add Confirmation for Destructive Actions

**Issue:** While `hx-confirm` is used for deletes, other destructive actions (logout, clear) have no confirmation.

**Location:** Various page files

**Action Required:** Review all destructive actions and add appropriate confirmations.

**Estimated Effort:** Small

---

### [Priority: Low] Add Favicon and PWA Support

**Issue:** No favicon is configured, and the app is not installable as a PWA.

**Location:**
- `/Users/Shared/Projects/lean-workspace/homebase-app/public/` (new assets)
- `/Users/Shared/Projects/lean-workspace/homebase-app/HomebaseApp/Shared.lean` (head section)

**Action Required:** Add favicon, web manifest, and service worker for PWA capabilities.

**Estimated Effort:** Medium

---

## Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Features | 0 | 3 | 5 | 4 |
| Improvements | 0 | 3 | 4 | 1 |
| Cleanup | 0 | 1 | 2 | 2 |
| Security | 1 | 3 | 2 | 1 |
| Performance | 0 | 0 | 2 | 2 |
| UX/UI | 0 | 1 | 4 | 2 |
| **Total** | **1** | **11** | **19** | **12** |

**Recommended Priority Order:**
1. Replace weak password hashing (Critical Security)
2. Enable CSRF protection (High Security)
3. Secure session secret key (High Security)
4. Consolidate duplicate code (High Cleanup/Improvement)
5. Implement placeholder sections (High Feature)
6. Add user profile page (High Feature)
7. Add loading states (High UX)
