# CLAUDE.md - Homebase App

Personal dashboard application built with Loom (Lean 4 web framework).

## Build & Run

```bash
lake build                        # Build the app
.lake/build/bin/homebaseApp       # Run on port 3000
lake test                         # Run unit tests
```

## Architecture

### Core Files
| File | Purpose |
|------|---------|
| `HomebaseApp/Main.lean` | App setup, routes, database config |
| `HomebaseApp/Models.lean` | Ledger attribute definitions |
| `HomebaseApp/Entities.lean` | Entity type definitions and TxM operations |
| `HomebaseApp/Shared.lean` | Layout, navigation, common HTML components |
| `HomebaseApp/Middleware.lean` | Auth middleware, request processing |
| `HomebaseApp/Helpers.lean` | Utility functions (slugify, sanitize, etc.) |
| `HomebaseApp/Upload.lean` | File upload handling |

### Pages
| File | Route | SSE Topic |
|------|-------|-----------|
| `Pages/Home.lean` | `/` | - |
| `Pages/Auth.lean` | `/login`, `/register`, `/logout` | - |
| `Pages/Kanban.lean` | `/kanban` | `kanban` |
| `Pages/Time.lean` | `/time` | `time` |
| `Pages/Gallery.lean` | `/gallery` | `gallery` |
| `Pages/Chat.lean` | `/chat` | `chat` |
| `Pages/Sections.lean` | `/notebook`, `/health`, `/recipes`, `/news` | - |
| `Pages/Admin.lean` | `/admin` | - |

### Tests
| File | Purpose |
|------|---------|
| `HomebaseApp/Tests/Kanban.lean` | Kanban pure function tests |
| `HomebaseApp/Tests/EntityPull.lean` | Entity pull/query tests |
| `HomebaseApp/Tests/Time.lean` | Time tracker pure function tests |
| `Tests/Main.lean` | Test runner entry point |

### Static Assets
```
public/
├── css/
│   ├── app.css      # Global styles
│   ├── kanban.css   # Kanban board styles
│   ├── time.css     # Time tracker styles
│   ├── gallery.css  # Gallery styles
│   └── chat.css     # Chat styles
└── js/
    ├── kanban.js    # Kanban SSE + drag-drop
    ├── chat.js      # Chat SSE + file upload
    ├── time.js      # Time SSE handling
    └── gallery.js   # Gallery SSE handling
```

## SSE (Server-Sent Events) Pattern

**All interactive pages MUST use SSE for real-time updates across browser tabs.**

### 1. Register Endpoint in Main.lean
```lean
-- In buildApp function:
|>.sseEndpoint "/events/topic" "topic"
```

### 2. Server-Side Event Publishing (Page.lean)
```lean
import Loom.SSE

-- After any mutation, publish an event:
let _ ← SSE.publishEvent "topic" "event-name" (jsonStr! { field1, field2 })
```

### 3. Client-Side JavaScript
```javascript
(function() {
  if (window._topicSSEInitialized) return;
  window._topicSSEInitialized = true;

  var eventSource = new EventSource('/events/topic');

  eventSource.addEventListener('event-name', function(e) {
    var data = JSON.parse(e.data);
    // Refresh relevant UI via HTMX
    htmx.ajax('GET', '/endpoint', {target: '#container', swap: 'innerHTML'});
  });

  // Cleanup on page unload
  window.addEventListener('beforeunload', function() {
    window._topicSSEInitialized = false;
    eventSource.close();
  });
})();
```

### 4. Include Script in Page Content
```lean
-- At end of page content function:
script [src_ "/js/topic.js"]
```

### SSE Topics & Events
| Topic | Events | Purpose |
|-------|--------|---------|
| `kanban` | `board-created`, `board-updated`, `board-deleted`, `column-created`, `column-updated`, `column-deleted`, `card-created`, `card-updated`, `card-deleted`, `card-moved`, `card-reordered` | Kanban board sync |
| `chat` | `thread-created`, `thread-updated`, `thread-deleted`, `message-added` | Chat sync |
| `time` | `timer-started`, `timer-stopped`, `entry-created`, `entry-updated`, `entry-deleted` | Time tracker sync |
| `gallery` | `item-uploaded`, `item-updated`, `item-deleted` | Gallery sync |

## Loom Patterns

### Page Definition
```lean
-- Read-only view (GET)
view pageName "/path" [middleware...] do
  let ctx ← getCtx
  html (Shared.render ctx "Title" "/path" content)

-- Mutation action (POST/PUT/DELETE)
action actionName "/path" POST [middleware...] do
  let ctx ← getCtx
  -- ... perform mutation ...
  let _ ← SSE.publishEvent "topic" "event" jsonData  -- Always publish!
  redirect "/path"
```

### HTMX Integration
```lean
-- Form that triggers page reload after success
form [hx_post "/action", hx_swap "none",
      attr_ "hx-on::after-request" "if(event.detail.successful) window.location.reload()"] do
  -- form fields

-- Partial update without reload
form [hx_post "/action", hx_target "#container", hx_swap "innerHTML"] do
  -- form fields
```

### Database (Ledger)
```lean
-- Create entity with audit
let (eid, _) ← withNewEntityAudit! fun eid => do
  let entity := { ... }
  DbEntity.TxM.create eid entity
  audit "CREATE" "entity-type" eid.id.toNat [("field", value)]

-- Update entity
runAuditTx! do
  DbEntity.TxM.setField eid newValue
  audit "UPDATE" "entity-type" id [("field", newValue)]

-- Query entities
let ids := db.findByAttrValue DbEntity.attr_field (.value val)
let entities := ids.filterMap fun id => DbEntity.pull db id
```

## Testing with Crucible

```lean
import Crucible

testSuite "Suite Name"

test "test description" := do
  result ≡ expected                    -- Equality assertion
  shouldSatisfy condition "message"    -- Condition assertion
  shouldContain list item              -- List containment

```

## Common Issues

### Wall Clock Time
Lean 4 lacks built-in wall clock time. Use the shell workaround:
```lean
def getNowMs : IO Nat := do
  let output ← IO.Process.output { cmd := "date", args := #["+%s"] }
  return output.stdout.trim.toNat?.getD 0 * 1000
```

### HTMX + Redirects
When using `hx_swap "none"`, redirects are ignored. Add:
```lean
attr_ "hx-on::after-request" "if(event.detail.successful) window.location.reload()"
```

### Entity IDs
```lean
let eid : EntityId := ⟨natId⟩           -- Create EntityId from Nat
let natId := eid.id.toNat               -- Extract Nat from EntityId
```
