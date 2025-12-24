# Homebase App

A personal dashboard web application built with Lean 4, featuring:

- **Loom** - Rails-like web framework
- **Ledger** - Datomic-like fact-based database
- **Citadel** - HTTP server
- **Scribe** - HTML generation

## Features

- Left sidebar navigation with 8 sections
- User registration and login (session-based authentication)
- Persistent database storage
- Flash messages for user feedback
- CSRF protection

## Sections

- **Chat** - Messaging (coming soon)
- **Notebook** - Notes and documents (coming soon)
- **Time** - Time tracking (coming soon)
- **Crohn's Disease** - Health tracking (coming soon)
- **Recipes** - Recipe collection (coming soon)
- **Kanban** - Task boards (coming soon)
- **Gallery** - Image gallery (coming soon)
- **News** - News feed (coming soon)

## Requirements

- Lean 4.26.0
- Lake (included with Lean)

## Building

```bash
# Build the library and executable
lake build

# Build just the executable
lake build homebaseApp
```

## Running

```bash
# Start the server
.lake/build/bin/homebaseApp
```

The server will start on `http://0.0.0.0:3000`.

## Routes

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Home page |
| GET | `/login` | Login form |
| POST | `/login` | Authenticate user |
| GET | `/register` | Registration form |
| POST | `/register` | Create new account |
| GET | `/logout` | Log out |
| GET | `/chat` | Chat section |
| GET | `/notebook` | Notebook section |
| GET | `/time` | Time tracking section |
| GET | `/health` | Health tracking section |
| GET | `/recipes` | Recipes section |
| GET | `/kanban` | Kanban board section |
| GET | `/gallery` | Gallery section |
| GET | `/news` | News section |

## Project Structure

```
homebase-app/
├── lakefile.lean           # Package configuration
├── lean-toolchain          # Lean version
├── HomebaseApp.lean        # Root module
├── public/
│   └── styles.css          # CSS styling
├── data/                   # Database storage
├── HomebaseApp/
│   ├── Models.lean         # Database attribute definitions
│   ├── Helpers.lean        # Auth guards, password hashing, utilities
│   ├── Actions/
│   │   ├── Home.lean       # Home page action
│   │   ├── Auth.lean       # Login, register, logout
│   │   ├── Chat.lean       # Chat section
│   │   ├── Notebook.lean   # Notebook section
│   │   ├── Time.lean       # Time section
│   │   ├── Health.lean     # Health section
│   │   ├── Recipes.lean    # Recipes section
│   │   ├── Kanban.lean     # Kanban section
│   │   ├── Gallery.lean    # Gallery section
│   │   └── News.lean       # News section
│   ├── Views/
│   │   ├── Layout.lean     # HTML layout with sidebar
│   │   ├── Home.lean       # Home page view
│   │   ├── Auth.lean       # Login/register forms
│   │   └── [section].lean  # Section views
│   └── Main.lean           # App configuration and routes
```

## Database Schema

The app uses Ledger's fact-based database with the following attributes:

**User:**
- `:user/email` - User's email address
- `:user/password-hash` - Hashed password
- `:user/name` - Display name

## Dependencies

- [Loom](../loom) - Web framework
- [Ledger](../ledger) - Database (via Loom)
- [Citadel](../citadel) - HTTP server (via Loom)
- [Scribe](../scribe) - HTML generation (via Loom)
- [Crucible](../crucible) - Test framework

## License

MIT License - see [LICENSE](LICENSE)
