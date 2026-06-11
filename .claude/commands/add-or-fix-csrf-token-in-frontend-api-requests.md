---
name: add-or-fix-csrf-token-in-frontend-api-requests
description: Workflow command scaffold for add-or-fix-csrf-token-in-frontend-api-requests in tududi.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /add-or-fix-csrf-token-in-frontend-api-requests

Use this workflow when working on **add-or-fix-csrf-token-in-frontend-api-requests** in `tududi`.

## Goal

Ensures API requests from frontend components include the CSRF token header to pass backend CSRF protection.

## Common Files

- `frontend/components/Project/BannerEditModal.tsx`
- `frontend/components/Project/ProjectDetails.tsx`
- `frontend/components/Profile/tabs/NotificationsTab.tsx`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Identify the frontend component making the API request.
- Import or use getCsrfToken from csrfService.
- Add the 'x-csrf-token' header to the fetch or axios request.
- Test the request to ensure backend accepts it.

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.