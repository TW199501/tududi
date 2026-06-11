```markdown
# tududi Development Patterns

> Auto-generated skill from repository analysis

## Overview

This skill teaches you the core development patterns, coding conventions, and common workflows used in the `tududi` repository—a React-based JavaScript application with a Node.js backend. You'll learn how to maintain consistency in code style, implement and test new features, and follow established procedures for handling authentication, CSRF protection, CalDAV protocol support, migrations, and date/time logic. This guide is ideal for contributors seeking to quickly onboard or maintain best practices in the codebase.

## Coding Conventions

**File Naming**
- Use `camelCase` for file names.
  - Example: `taskDetails.js`, `projectBannerEditModal.tsx`

**Imports**
- Use relative import paths.
  - Example:
    ```js
    import { getCsrfToken } from '../../services/csrfService';
    ```

**Exports**
- Use named exports.
  - Example:
    ```js
    export function validateTaskDate(date) { ... }
    ```

**Commit Messages**
- Follow [Conventional Commits](https://www.conventionalcommits.org/) with prefixes like `fix`, `release`.
  - Example: `fix: handle timezone edge case in recurring tasks`

## Workflows

### Add or Fix CSRF Token in Frontend API Requests
**Trigger:** When adding a new API call or fixing a bug where a frontend request is rejected due to missing CSRF token.  
**Command:** `/add-csrf-token`

1. Identify the frontend component making the API request.
2. Import or use `getCsrfToken` from `csrfService`.
3. Add the `'x-csrf-token'` header to the fetch or axios request.
4. Test the request to ensure the backend accepts it.

**Example:**
```js
import { getCsrfToken } from '../../services/csrfService';

fetch('/api/projects', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'x-csrf-token': getCsrfToken(),
  },
  body: JSON.stringify(data),
});
```

### Fix CalDAV Protocol or Compatibility Issues
**Trigger:** When a CalDAV client fails to connect, sync, or discover calendars due to missing endpoints or protocol quirks.  
**Command:** `/fix-caldav`

1. Identify the failing CalDAV operation or endpoint (e.g., PROPFIND, REPORT, discovery).
2. Update or add handler in `backend/modules/caldav/` (such as `routes.js`, `protocol/discovery.js`, `webdav/*.js`, `api/*-controller.js`).
3. Add or update integration/unit tests for the new/fixed behavior.
4. Test with the target CalDAV client (e.g., iOS Reminders).

**Example:**
```js
// backend/modules/caldav/webdav/propfind.js
export function handlePropfind(req, res) {
  // Ensure correct namespace and response for iOS compatibility
}
```

### Backend Migration JSON Fix
**Trigger:** When a migration fails or corrupts data due to incorrect JSON parsing or encoding.  
**Command:** `/fix-json-migration`

1. Identify the migration file and the affected column.
2. Add `JSON.parse` (possibly multiple times) before property access.
3. Conditionally update DB rows only when needed.
4. Test migration on real or test data to ensure idempotency and correctness.

**Example:**
```js
// backend/migrations/20251209000001-add-telegram-to-notification-preferences.js
const prefs = JSON.parse(JSON.parse(row.preferences));
if (!prefs.telegram) {
  // update logic
}
```

### Add or Update Backend Auth Middleware
**Trigger:** When adding a new auth method, fixing bypasses, or making auth checks more robust.  
**Command:** `/update-auth-middleware`

1. Update or add logic in `backend/middleware/auth.js` or related modules.
2. Update provider config or token validation logic.
3. Add or update tests for the new or fixed behavior.
4. Document any new environment variables or config options.

**Example:**
```js
// backend/middleware/auth.js
export function requireAuth(req, res, next) {
  // Check for OIDC, OAuth2, or API token
}
```

### Fix Timezone or Date Handling in Tasks
**Trigger:** When users report tasks showing on wrong days or validation errors for same-day defer/due.  
**Command:** `/fix-task-timezone`

1. Update backend date parsing/validation logic (`recurringTaskService.js`, `validation.js`, etc).
2. Update frontend date parsing/display logic (`TaskRecurrenceCard.tsx`, `TaskDetails.tsx`).
3. Add or update tests to cover edge cases (timezones, same-day, etc).

**Example:**
```js
// backend/modules/tasks/utils/validation.js
export function validateTaskDate(date, timezone) {
  // Use timezone-aware date library (e.g., luxon)
}
```

## Testing Patterns

- **Framework:** [Jest](https://jestjs.io/)
- **Test File Pattern:** `*.test.js`
- **Placement:** Tests are located alongside modules or in dedicated `tests/` directories.
- **Example:**
  ```js
  // backend/tests/unit/utils/validation.test.js
  import { validateTaskDate } from '../../../modules/tasks/utils/validation';

  test('should validate same-day defer and due dates', () => {
    expect(validateTaskDate('2024-06-01', 'UTC')).toBe(true);
  });
  ```

## Commands

| Command               | Purpose                                                        |
|-----------------------|----------------------------------------------------------------|
| /add-csrf-token       | Add or fix CSRF token headers in frontend API requests         |
| /fix-caldav           | Implement or correct CalDAV protocol endpoints or handlers     |
| /fix-json-migration   | Fix Sequelize migrations handling JSON columns                 |
| /update-auth-middleware | Add or update backend authentication/authorization middleware |
| /fix-task-timezone    | Fix timezone or date handling in task logic                    |
```
