# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Tududi - Developer Guide

This documentation is designed for AI assistants and developers working with the tududi codebase. For user-facing documentation, see [README.md](README.md). For contribution guidelines, see [CONTRIBUTING.md](.github/CONTRIBUTING.md).

---

## Quick Start

Tududi is a self-hosted task management system with hierarchical organization (Areas > Projects > Tasks), smart recurring tasks, and multi-channel integration.

**Tech Stack:** React 18 + TypeScript, Express + Sequelize, SQLite

**Get Started:**
```bash
git clone https://github.com/chrisvel/tududi.git
cd tududi
npm install
npm run db:init
npm start  # Frontend on :8080, Backend on :3002
```

---

## Common Commands

All commands run from the repo root unless noted. Scripts are split into `frontend:*` / `backend:*` variants; the un-prefixed aliases (`lint`, `format`) run both.

**Run / develop**
```bash
npm start              # Both servers via scripts/start-all-dev.sh (frontend :8080, backend :3002)
npm run frontend:dev   # Webpack dev server only (proxies /api to backend on :3002)
npm run backend:dev    # Backend only, nodemon-watched
npm run kill:all       # Free ports 8080 and 3002 if a server is stuck
```

**Build / lint / format** (CI runs `npm run lint` then build — both must pass)
```bash
npm run build          # Frontend production build: tsc --noEmit + webpack -> dist/
npm run lint           # ESLint frontend + backend
npm run lint:fix       # Auto-fix lint
npm run format:fix     # Prettier write frontend + backend
```

**Tests**
```bash
npm test               # = backend:test (Jest, NODE_ENV=test, run from backend/)
npm run frontend:test  # Frontend Jest (jsdom, ts-jest) — note: NOT included in `npm test`
npm run test:ui        # Playwright E2E via e2e/bin/run-e2e.sh
npm run backend:test:unit         # backend/tests/unit only
npm run backend:test:integration  # backend/tests/integration only

# Run a single backend test file or by name (Jest lives in backend/):
cd backend && cross-env NODE_ENV=test npx jest tests/unit/tasks/recurring.test.js
cd backend && cross-env NODE_ENV=test npx jest -t "creates a recurring task"
# Single frontend test:
npx jest frontend/utils/dateUtils.test.ts
```

**Database & migrations** (all proxy into `backend/`)
```bash
npm run db:init          # Initialize DB + first user
npm run db:migrate       # Run pending migrations
npm run db:status        # Show migration status
npm run db:reset         # Drop + recreate
npm run db:reset-and-seed   # Reset then seed dev data (NODE_ENV=development)
npm run migration:create    # Scaffold a new migration in backend/migrations/
npm run migration:undo      # Roll back the last migration
npm run user:create         # Create a user interactively
```

Backend tests must run with `NODE_ENV=test` (the npm scripts set this). Several backend features are gated behind feature flags that default to off locally — CI enables `FF_ENABLE_BACKUPS`, `FF_ENABLE_CALDAV`, `FF_ENABLE_CALENDAR` when running backend tests. See `backend/.env.example` for all `FF_*` and `DISABLE_*` flags.

**Fork / upstream workflow** (this `dev` branch tracks a downstream fork of `chrisvel/tududi`; these scripts are not present on upstream `main`)
```bash
npm run upstream:sync    # Sync this fork from upstream (scripts/sync-upstream.sh)
npm run upstream:pr      # Open a PR back to upstream (scripts/pr-to-upstream.sh)
npm run release          # Tag/cut a release (scripts/release.sh)
```

---

## Architecture at a Glance

The big-picture wiring that spans multiple files (read `backend/app.js` alongside any one module to see the full pattern):

**Backend is a modular monolith.** Each feature lives in `backend/modules/<name>/` and exposes a router via its `index.js` (`module.exports = { routes }`). `app.js` imports every module and mounts it under a versioned base path:

```js
// backend/app.js
const API_BASE_PATH = `/api/${process.env.API_VERSION || 'v1'}`;
app.use(basePath, authModule.routes);        // public auth routes first
app.use(`${basePath}/oidc`, oidcModule.routes);
app.use(basePath, requireAuth);              // <-- everything mounted AFTER this line is auth-gated
app.use(basePath, tasksModule.routes);
app.use(basePath, projectsModule.routes);
// ...all other modules
```

So **ordering in `app.js` matters**: routes registered before `app.use(basePath, requireAuth)` are public; everything after requires a session. `oauthRoutes` and `caldavRoutes` are mounted at the root (not under `basePath`) because external clients call them on fixed paths.

**Inside a module**, responsibilities are split into conventional files (the `tasks` module is the richest example):
- `routes.js` — Express handlers, request/response only
- `repository.js` — Sequelize data access
- `*Service.js` — business logic (e.g. `recurringTaskService.js`, `deferredTaskService.js`)
- `core/`, `operations/`, `queries/`, `utils/` — serializers, builders, query-builders, validation

To add a module: create `backend/modules/<name>/{index.js,routes.js,repository.js}`, then add one import + one `app.use(basePath, <name>Module.routes)` line in `app.js`. See [docs/backend-patterns.md](docs/backend-patterns.md).

**Models** live flat in `backend/models/`, registered through `models/index.js` (Sequelize). Migrations in `backend/migrations/` are the source of truth for schema — never hand-edit applied migrations; add a new one.

**Auth is multi-modal:** session cookies (`express-session` + `connect-session-sequelize`), personal API tokens, OAuth, OIDC, and CalDAV calendar tokens all coexist. `requireAuth` is the session gate; tokens/oauth are handled by their own middleware/modules.

**Frontend** is a single React SPA (`frontend/index.tsx` -> `App.tsx` -> `Layout.tsx`). Data flow:
- One global Zustand store: `frontend/store/useStore.ts`
- Server state via SWR + per-resource service clients in `frontend/utils/<resource>Service.ts` (e.g. `tasksService.ts`) — these are the API boundary; components call services, not `fetch` directly
- In dev the webpack server (`webpack.config.js`) proxies `/api` -> `http://localhost:3002`, forwarding cookies for session auth

**Background work:** `node-cron` schedulers (e.g. `backend/modules/tasks/taskScheduler.js`, CalDAV sync) start from `app.js`; disable with `DISABLE_SCHEDULER=true`. Telegram polling starts similarly (`DISABLE_TELEGRAM=true` to skip).

---

## Documentation Index

### Core Documentation

1. **[Architecture Overview](docs/architecture.md)**
   - Tech stack details
   - Request flow diagram
   - Data model hierarchy
   - Authentication methods

2. **[Directory Structure](docs/directory-structure.md)**
   - Complete file tree with absolute paths
   - Critical paths reference
   - Backend and frontend organization

3. **[Backend Patterns](docs/backend-patterns.md)**
   - Module architecture pattern
   - How to add new modules
   - Module communication
   - Repository and service patterns

4. **[Database & Migrations](docs/database.md)**
   - Key models and relationships
   - Migration workflow
   - Migration best practices
   - Common migration operations

5. **[Backups & Restoration](docs/backups.md)**
   - Automatic SQLite file backups before migrations
   - Backup retention policies (4 per day, 1 per day for 7 days)
   - Restoration procedures for development, Docker, and production
   - Emergency restore after failed migrations
   - Best practices for data safety

6. **[Development Workflow](docs/development-workflow.md)**
   - Initial setup
   - Daily development (two-server process)
   - Environment variables
   - Adding new features (complete walkthrough)
   - Database management commands

7. **[Code Conventions](docs/code-conventions.md)**
   - Language usage (TypeScript/JavaScript)
   - Backend patterns (async/await, repository)
   - Frontend patterns (components, state)
   - Naming conventions
   - API route conventions

8. **[Testing](docs/testing.md)**
   - Test organization
   - Running tests
   - Testing requirements
   - Test patterns (Arrange-Act-Assert)

9. **[Common Tasks](docs/common-tasks.md)**
   - Add field to model
   - Create new backend module
   - Add React component
   - Update database schema
   - Fix a bug (TDD workflow)
   - Add translations

10. **[Tasks Behavior](docs/00-tasks-behavior.md)**
    - Task creation and basic fields
    - Status lifecycle and priority levels
    - Due dates and Defer Until
    - Subtasks and hierarchy
    - File attachments
    - Project assignment and tags
    - Task completion and history
    - Habit mode and tracking
    - Task deletion and permissions

11. **[Recurring Tasks Behavior](docs/01-recurring-tasks-behavior.md)**
    - How recurring tasks work (non-technical rules)
    - Completion behavior and patterns
    - Virtual instances and display rules
    - Parent-child relationships
    - Editing and deletion behavior

12. **[Today Page Sections](docs/02-today-page-sections.md)**
    - How Overdue, Planned, Suggested, and Completed sections work
    - Task filtering and display rules
    - Section priority and deduplication logic
    - User settings and customization
    - Defer Until and timezone handling

13. **[Upcoming View](docs/03-upcoming-view.md)**
    - How the 7-day Upcoming view works
    - Day-based grouping and organization
    - Recurring task virtual occurrences
    - Defer Until and status filtering
    - Differences from Today view

14. **[Inbox Page](docs/04-inbox-page.md)**
    - Quick capture system for unorganized thoughts
    - Smart parsing of hashtags, projects, and URLs
    - Intelligent suggestions (Task vs Note vs Project)
    - Converting inbox items to structured content
    - Telegram integration and auto-refresh
    - Keyboard shortcuts and workflows

15. **[Notes System](docs/05-notes-system.md)**
    - Flexible information and reference storage
    - Markdown support and rich text rendering
    - Auto-save functionality (1-second debounce)
    - Project linking and tag-based organization
    - Focus mode for distraction-free writing
    - Color customization for visual organization
    - Integration with inbox and project workflows

16. **[Projects](docs/06-projects.md)**
    - Project hierarchy and organization (Areas > Projects > Tasks)
    - Status lifecycle and stalled detection
    - Completion tracking and progress metrics
    - Project sharing and collaboration permissions
    - Due dates, notifications, and priorities
    - Deletion behavior (orphaning vs cascading)
    - Filtering, grouping, and sidebar pinning

17. **[Areas](docs/07-areas.md)**
    - Top-level organizational categories for life domains
    - Simple structure with name and description
    - Optional containers for grouping projects
    - Cascade behavior when deleting (orphans projects)
    - Grid view with alphabetical sorting
    - Integration with Projects page filtering and grouping

18. **[Views System](docs/08-views-system.md)**
    - Smart saved searches for tasks, notes, and projects
    - Creating views from Universal Search
    - Pinning and reordering views in sidebar
    - Filtering, sorting, and grouping within views
    - View management (rename, delete, pin/unpin)
    - URL parameters and deep linking
    - Pagination and performance

19. **[User Management](docs/08-user-management.md)**
    - Registration flow and email verification
    - Authentication (session-based and API tokens)
    - User roles and admin system
    - Resource permissions and sharing
    - Profile management and preferences
    - Password and avatar management
    - API token management
    - Admin user CRUD operations

20. **[Tags System](docs/09-tags-system.md)**
    - Cross-entity labeling and categorization (tasks, notes, projects)
    - Auto-creation and validation rules
    - Tag management (create, edit, delete, rename)
    - Tag detail pages with filtering and search
    - Alphabetical grouping and organization
    - Hashtag parsing from inbox items
    - Tag input component with autocomplete

21. **[Claude Memory & Preferences](docs/MEMORY.md)**
    - PR and commit message preferences
    - Testing preferences
    - Common patterns to remember
    - Known issues and solutions

---

## Project Overview

### What This Project Does

Tududi is a self-hosted task management system designed around hierarchical organization and smart automation. It prioritizes user flow over rigid structures - a productivity tool that doesn't "fight back."

**Core Philosophy:**
- [Designing a Life Management System That Doesn't Fight Back](https://medium.com/@chrisveleris/designing-a-life-management-system-that-doesnt-fight-back-2fd58773e857)
- [From Task to Table: How I Finally Got to the Korean Burger](https://medium.com/@chrisveleris/from-task-to-table-how-i-finally-got-to-the-korean-burger-01245a14d491)

**Key Capabilities:**
- **Hierarchical Organization:** Areas > Projects > Tasks > Subtasks
- **Smart Recurring Tasks:** Multiple patterns with parent-child tracking
- **Multi-Language Support:** 24 languages via i18next
- **Collaboration:** Project sharing with granular permissions
- **REST API:** Swagger docs + personal API tokens
- **Telegram Integration:** Create tasks via messages, daily digests
- **Tag System:** Flexible tagging across tasks, notes, projects

**Target Users:** Self-hosting individuals and teams managing personal or collaborative productivity

---

## Technology Stack

**Frontend:**
- React 18 + TypeScript 5.6
- Webpack 5 (build) + webpack-dev-server (development)
- Tailwind CSS 3.4 + Heroicons
- Zustand (global state) + SWR (server state)
- React Router 6, i18next (24 languages)

**Backend:**
- Express 4.21 + Sequelize 6.37 (ORM)
- SQLite 5.1 (WAL mode, optimized)
- bcrypt + express-session (auth)
- Swagger (API docs), Multer (uploads)
- node-cron (scheduling), Nodemailer (email)

**Testing:**
- Jest (backend + frontend)
- Playwright (E2E)
- Supertest (API integration tests)

---

## Critical Paths Quick Reference

| Task | Location |
|------|----------|
| Add backend feature | `/backend/modules/[feature]/` |
| Create model | `/backend/models/[model].js` |
| Database migration | `/backend/migrations/` |
| React component | `/frontend/components/[Feature]/` |
| API routes | `/backend/modules/[module]/routes.js` |
| Global state | `/frontend/store/useStore.ts` |
| API client | `/frontend/utils/[resource]Service.ts` |

---

## Related Documentation

| Document | Audience | Purpose |
|----------|----------|---------|
| [README.md](README.md) | Users | Features, Docker setup, quick start |
| [CONTRIBUTING.md](.github/CONTRIBUTING.md) | Contributors | PR workflow, code of conduct |
| [docs.tududi.com](https://docs.tududi.com) | End users | Full user documentation |
| [Swagger API docs](http://localhost:3002/api-docs) | API consumers | API endpoints (after auth) |
| **CLAUDE.md** | Developers, AI | Codebase architecture, patterns |

---

## External Resources

- **Roadmap:** [GitHub Project](https://github.com/users/chrisvel/projects/2)
- **Community:**
  - [Discord](https://discord.gg/fkbeJ9CmcH)
  - [Reddit](https://www.reddit.com/r/tududi/)
  - [Issues](https://github.com/chrisvel/tududi/issues)
  - [Discussions](https://github.com/chrisvel/tududi/discussions)

---

**Document Version:** 1.0.0
**Last Updated:** 2026-03-14
**Maintainer:** Update when architecture changes or patterns evolve
