# Roadmap - Homebase App

This document tracks proposed improvements, new features, and code cleanup opportunities for the Homebase App codebase.

---

## Feature Proposals

### [Priority: High] User Profile and Settings Page
**Description:** Add a user profile page where users can update their name, email, password, and preferences.
**Rationale:** Currently users can only be managed through the admin panel. Users should be able to manage their own account settings.
**Affected Files:**
- `HomebaseApp/Pages/Profile.lean` (new)
- `HomebaseApp/StencilHelpers.lean` (add PageId.profile)
- `HomebaseApp/Shared.lean` (add profile link to navbar)
- `templates/profile/` (new directory)
**Estimated Effort:** Medium
**Dependencies:** None

### [Priority: High] Password Reset / Forgot Password Flow
**Description:** Implement a password reset flow with email verification or security questions.
**Rationale:** Users who forget their password currently have no way to recover their account. This is a critical security and UX feature.
**Affected Files:**
- `HomebaseApp/Pages/Auth.lean`
- `HomebaseApp/Models.lean` (add password reset token entity)
- `templates/auth/forgot-password.html.hbs` (new)
- `templates/auth/reset-password.html.hbs` (new)
**Estimated Effort:** Large
**Dependencies:** Email sending capability (would need SMTP integration or similar)

### [Priority: High] Search Across All Modules
**Description:** Add a global search feature that searches across notes, recipes, kanban cards, chat messages, and news items.
**Rationale:** As data grows, users need a quick way to find information across all modules. Currently only chat has search.
**Affected Files:**
- `HomebaseApp/Pages/Search.lean` (new)
- `HomebaseApp/Shared.lean` (add search bar to layout)
- `templates/search/` (new directory)
**Estimated Effort:** Large
**Dependencies:** None

### [Priority: Medium] Data Export/Backup Feature
**Description:** Allow users to export their data (notes, recipes, time entries, etc.) in JSON or other formats.
**Rationale:** Users should be able to backup and migrate their personal data. Supports data portability.
**Affected Files:**
- `HomebaseApp/Pages/Admin.lean` (for admin-level export)
- `HomebaseApp/Pages/Profile.lean` (for user-level export)
**Estimated Effort:** Medium
**Dependencies:** User Profile page (for user-level export)

### [Priority: Medium] Recurring Time Entries
**Description:** Add support for recurring/scheduled time entries in the time tracker.
**Rationale:** Many users track regular activities (daily standup, weekly meetings). Automating this would save time.
**Affected Files:**
- `HomebaseApp/Models.lean` (add DbRecurringEntry)
- `HomebaseApp/Entities.lean`
- `HomebaseApp/Pages/Time.lean`
- `templates/time/` (add recurring entry forms)
**Estimated Effort:** Large
**Dependencies:** Proper wall clock time implementation (see Code Improvements section)

### [Priority: Medium] Kanban Board Sharing/Collaboration
**Description:** Allow users to share kanban boards with other users for collaboration.
**Rationale:** Multi-user collaboration is a natural extension for a household dashboard app.
**Affected Files:**
- `HomebaseApp/Models.lean` (add DbBoardMember for board sharing)
- `HomebaseApp/Pages/Kanban.lean`
- `templates/kanban/share.html.hbs` (new)
**Estimated Effort:** Large
**Dependencies:** None

### [Priority: Medium] Recipe Import from URL
**Description:** Auto-populate recipe fields by scraping recipe websites.
**Rationale:** Most users find recipes online. Importing saves manual data entry.
**Affected Files:**
- `HomebaseApp/Pages/Recipes.lean`
- `HomebaseApp/Embeds.lean` (reuse URL fetching logic)
- `templates/recipes/import.html.hbs` (new)
**Estimated Effort:** Medium
**Dependencies:** None

### [Priority: Medium] Calendar View for Time Tracking
**Description:** Add a calendar/heatmap view showing time logged per day.
**Rationale:** Visual representation helps users understand their time allocation patterns.
**Affected Files:**
- `HomebaseApp/Pages/Time.lean`
- `templates/time/calendar.html.hbs` (new)
- `public/css/time.css`
- `public/js/time.js`
**Estimated Effort:** Medium
**Dependencies:** None

### [Priority: Medium] Health Data Visualization/Charts
**Description:** Add charts showing weight trends, exercise patterns over time.
**Rationale:** Health tracking is most valuable with trend visualization.
**Affected Files:**
- `HomebaseApp/Pages/Health.lean`
- `templates/health/charts.html.hbs` (new)
- `public/js/health.js` (add charting library integration)
**Estimated Effort:** Medium
**Dependencies:** None

### [Priority: Low] Markdown Preview in Notebook
**Description:** Add live markdown preview when editing notes.
**Rationale:** Users write in markdown but cannot see formatted output until saving.
**Affected Files:**
- `templates/notebook/` (add preview pane)
- `public/js/notebook.js` (add markdown rendering)
**Estimated Effort:** Small
**Dependencies:** Markdown rendering library (client-side)

### [Priority: Low] Dark Mode Theme
**Description:** Add a dark mode toggle for the UI.
**Rationale:** Many users prefer dark mode, especially for evening use.
**Affected Files:**
- `public/css/app.css` (add dark theme variables)
- `public/css/*.css` (update all CSS files)
- `HomebaseApp/Shared.lean` (add theme toggle)
- `public/js/theme.js` (new)
**Estimated Effort:** Medium
**Dependencies:** None

### [Priority: Low] Keyboard Shortcuts
**Description:** Add keyboard shortcuts for common actions (new note, start timer, etc.).
**Rationale:** Power users expect keyboard navigation for efficiency.
**Affected Files:**
- `public/js/*.js` (add keyboard event handlers)
- `templates/layouts/` (add shortcut documentation)
**Estimated Effort:** Small
**Dependencies:** None

---

## Code Improvements

### [Priority: Critical] Fix Wall Clock Time Implementation
**Current State:** Multiple pages use different time-getting methods:
- `Chat.lean` uses `IO.monoNanosNow / 1000000` (monotonic time - incorrect for timestamps)
- `Time.lean` uses shell `date +%s` command (correct but inefficient)
- `Gallery.lean` uses `IO.monoMsNow` (monotonic time - incorrect)
- `Notebook.lean`, `Health.lean`, `Recipes.lean`, `News.lean` all use shell `date +%s`
**Proposed Change:** Create a centralized `HomebaseApp.Time` module with a proper wall clock time function. All pages should use this single implementation.
**Benefits:** Correctness (timestamps represent actual dates), consistency, maintainability, performance (reduce shell spawning).
**Affected Files:**
- `HomebaseApp/Time.lean` (new module)
- All Pages/*.lean files
**Estimated Effort:** Medium
**Note:** The test file `Tests/Time.lean` explicitly documents this bug at line 222-239.

### [Priority: High] Extract Duplicated Helper Functions
**Current State:** Multiple helper functions are duplicated across pages:
- `getCurrentUserEid` is defined in Time.lean, Gallery.lean, Notebook.lean, Health.lean, Recipes.lean, News.lean
- `formatRelativeTime` is defined in Chat.lean, Gallery.lean, Notebook.lean, Health.lean, News.lean (with slight variations)
- `getNowMs`/`getTimeMs` equivalents exist in every page
**Proposed Change:** Create `HomebaseApp.Utils.lean` module with shared helper functions.
**Benefits:** DRY principle, consistent behavior, easier maintenance.
**Affected Files:**
- `HomebaseApp/Utils.lean` (new)
- All Pages/*.lean files
**Estimated Effort:** Medium
**Dependencies:** None

### [Priority: High] Consolidate isLoggedIn and isAdmin Functions
**Current State:** `isLoggedIn` and `isAdmin` are defined in multiple places:
- `HomebaseApp/Shared.lean` (lines 18-25)
- `HomebaseApp/Middleware.lean` (lines 11-16)
- `HomebaseApp/Helpers.lean` (lines 49-66)
Many pages use `hiding isLoggedIn isAdmin` to avoid conflicts.
**Proposed Change:** Define these functions in a single authoritative location and import consistently.
**Benefits:** Eliminates confusion, reduces `hiding` directives, cleaner imports.
**Affected Files:**
- `HomebaseApp/Auth.lean` (new, centralized auth functions)
- `HomebaseApp/Shared.lean`
- `HomebaseApp/Middleware.lean`
- `HomebaseApp/Helpers.lean`
- All Pages/*.lean files
**Estimated Effort:** Medium
**Dependencies:** None

### [Priority: High] Add Input Validation
**Current State:** Input validation is minimal. For example:
- Email format is not validated during registration
- Password strength is not enforced
- URL format validation in News and Embeds is basic
**Proposed Change:** Add comprehensive input validation with proper error messages.
**Benefits:** Security, data integrity, better UX.
**Affected Files:**
- `HomebaseApp/Validation.lean` (new module)
- `HomebaseApp/Pages/Auth.lean`
- `HomebaseApp/Pages/News.lean`
- Other pages as needed
**Estimated Effort:** Medium
**Dependencies:** None

### [Priority: Medium] Improve Error Handling in Embeds Module
**Current State:** `Embeds.lean` contains extensive debug logging with `IO.println` statements (lines 280-323) that should not be in production code.
**Proposed Change:** Replace `IO.println` debug statements with proper logging via Chronicle, or remove them entirely. Add structured error handling.
**Benefits:** Cleaner logs, better observability, production-ready code.
**Affected Files:**
- `HomebaseApp/Embeds.lean`
**Estimated Effort:** Small
**Dependencies:** None

### [Priority: Medium] Optimize Database Queries
**Current State:** Several database access patterns could be optimized:
- `getBoards`, `getColumnsWithCards`, etc. often fetch all entities then filter
- No pagination support for large datasets
- Multiple queries where a single query could suffice
**Proposed Change:** Add pagination support to list views. Optimize query patterns where possible.
**Benefits:** Better performance with large datasets, improved scalability.
**Affected Files:**
- All Pages/*.lean files with list views
- Template files (add pagination controls)
**Estimated Effort:** Large
**Dependencies:** None

### [Priority: Medium] Type-Safe Route Parameters
**Current State:** Route parameters are extracted as strings and manually parsed to Nat (e.g., `idStr.toNat?`). This pattern is repeated in many places.
**Proposed Change:** Use the existing `withId` helper from Helpers.lean more consistently, or enhance the routing system to support typed parameters.
**Benefits:** Less boilerplate, consistent error handling, type safety.
**Affected Files:**
- All Pages/*.lean files
**Estimated Effort:** Medium
**Dependencies:** None

### [Priority: Medium] Standardize Stencil Value Conversion
**Current State:** Each page has its own `*ToValue` functions (e.g., `cardToValue`, `messageToValue`, `recipeToValue`) with similar patterns.
**Proposed Change:** Create a generic conversion mechanism or use Lean's deriving for JSON/Stencil serialization.
**Benefits:** Less boilerplate, consistency, easier maintenance.
**Affected Files:**
- All Pages/*.lean files
**Estimated Effort:** Large
**Dependencies:** May require Ledger/Stencil library enhancements

### [Priority: Low] Add Request Rate Limiting
**Current State:** No rate limiting on authentication endpoints or API calls.
**Proposed Change:** Add rate limiting middleware, especially for login/register endpoints.
**Benefits:** Security against brute force attacks.
**Affected Files:**
- `HomebaseApp/Middleware.lean`
- `HomebaseApp/Main.lean`
**Estimated Effort:** Medium
**Dependencies:** May require Loom library enhancement

### [Priority: Low] Add CSRF Protection
**Current State:** CSRF protection is disabled in config (line 23 of Main.lean: `csrfEnabled := false`).
**Proposed Change:** Enable and properly configure CSRF protection.
**Benefits:** Security against cross-site request forgery attacks.
**Affected Files:**
- `HomebaseApp/Main.lean`
- All forms in templates
**Estimated Effort:** Small
**Dependencies:** None

---

## Code Cleanup

### [Priority: High] Remove Hardcoded Secret Key
**Issue:** `Main.lean` line 20-21 contains a hardcoded secret key: `secretKey := "homebase-app-secret-key-min-32-chars!!".toUTF8`
**Location:** `/Users/Shared/Projects/lean-workspace/apps/homebase-app/HomebaseApp/Main.lean:20-21`
**Action Required:** Move secret key to environment variable or configuration file.
**Estimated Effort:** Small

### [Priority: High] Remove Debug Print Statements
**Issue:** `Embeds.lean` contains many debug print statements that should not be in production.
**Location:** `/Users/Shared/Projects/lean-workspace/apps/homebase-app/HomebaseApp/Embeds.lean:280-323`
**Action Required:** Remove or replace with proper logging.
**Estimated Effort:** Small

### [Priority: Medium] Consolidate Password Hashing Functions
**Issue:** `hashPassword` and `verifyPassword` are defined in both `Helpers.lean` (lines 17-28) and `Auth.lean` (lines 23-33).
**Location:**
- `/Users/Shared/Projects/lean-workspace/apps/homebase-app/HomebaseApp/Helpers.lean:17-28`
- `/Users/Shared/Projects/lean-workspace/apps/homebase-app/HomebaseApp/Pages/Auth.lean:23-33`
**Action Required:** Keep only one implementation, preferably in Helpers.lean, and remove the duplicate.
**Estimated Effort:** Small

### [Priority: Medium] Clean Up Unused Legacy Code
**Issue:** `Kanban.lean` contains legacy compatibility functions like `getColumns` (line 93-101) and `getColumnsWithCards` (line 126-134) that may no longer be needed after board migration.
**Location:** `/Users/Shared/Projects/lean-workspace/apps/homebase-app/HomebaseApp/Pages/Kanban.lean:93-134`
**Action Required:** Verify if these functions are still needed; if not, remove them.
**Estimated Effort:** Small

### [Priority: Medium] Standardize File Naming Conventions
**Issue:** Test file `Tests/Stencil.lean` is imported in `Tests/Main.lean` but the file path structure differs from other test files (other tests are in `HomebaseApp/Tests/`).
**Location:** `/Users/Shared/Projects/lean-workspace/apps/homebase-app/Tests/Main.lean`
**Action Required:** Either move `Stencil.lean` tests to `HomebaseApp/Tests/Stencil.lean` or document the different conventions.
**Estimated Effort:** Small

### [Priority: Low] Add Missing Test Coverage
**Issue:** Several modules lack test coverage:
- `Auth.lean` - no authentication flow tests
- `Admin.lean` - no admin CRUD tests
- `Gallery.lean` - no tests
- `Notebook.lean` - no tests
- `Health.lean` - no tests
- `Recipes.lean` - no tests
- `News.lean` - no tests
- `Chat.lean` - no tests
- `Embeds.lean` - no tests
**Location:** `/Users/Shared/Projects/lean-workspace/apps/homebase-app/HomebaseApp/Tests/`
**Action Required:** Add unit tests for pure functions and integration tests for page handlers.
**Estimated Effort:** Large

### [Priority: Low] Document API Endpoints
**Issue:** No API documentation exists. The CLAUDE.md provides route information but not request/response formats.
**Location:** Project root
**Action Required:** Add API documentation, either in CLAUDE.md or a separate API.md file.
**Estimated Effort:** Medium

### [Priority: Low] Clean Up CSS Duplication
**Issue:** Similar styles are repeated across multiple CSS files (e.g., card styles, button styles, form styles).
**Location:** `/Users/Shared/Projects/lean-workspace/apps/homebase-app/public/css/`
**Action Required:** Extract common styles into `app.css` or create a shared components CSS file.
**Estimated Effort:** Medium

### [Priority: Low] Remove Unused Imports
**Issue:** Some files import modules that may not be fully used (e.g., `Scribe` in files that primarily use Stencil).
**Location:** Various Pages/*.lean files
**Action Required:** Audit imports and remove unused ones.
**Estimated Effort:** Small

---

## Architecture Considerations

### Database Schema Evolution
The app uses Ledger (a fact-based database) which is append-only. Consider:
- Adding schema versioning mechanism
- Migration strategy for attribute name changes
- Cleanup strategy for retracted facts

### Separation of Concerns
Consider splitting the monolithic page files into:
- **Controllers:** Route handlers and request/response logic
- **Services:** Business logic and database operations
- **Views:** Stencil value conversion and template rendering

### SSE Event Standardization
Different pages publish events with varying payload structures. Consider:
- Standardizing event payload format
- Creating typed event structures
- Centralizing event publishing logic

### Security Audit Needed
Areas requiring security review:
- File upload handling in `Upload.lean`
- URL fetching in `Embeds.lean` (SSRF potential)
- Session management
- Path traversal protection in `isSafePath`
