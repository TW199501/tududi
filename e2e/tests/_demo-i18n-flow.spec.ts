import { test } from '@playwright/test';

/**
 * Demo-only spec — produces a recorded video of the i18n investigation flow
 * for the demo HTML. NOT part of the regular E2E suite (filename prefixed with `_`).
 *
 * Run:
 *   E2E_SLOWMO=120 npx playwright test e2e/tests/_demo-i18n-flow.spec.ts \
 *     --project=Chromium --headed=false
 *
 * Output:
 *   test-results/_demo-i18n-flow-i18n-investigation--Chromium/video.webm
 */

// Override global config: record video, deterministic viewport
test.use({
    video: 'on',
    viewport: { width: 1280, height: 800 },
});

test('i18n investigation flow — clear → detect zh-TW → login → today in zh-TW', async ({
    page,
    context,
}) => {
    // ---- Pre-flight: wipe all browser state ----
    await context.clearCookies();
    await page.goto('/');
    await page.evaluate(() => {
        localStorage.clear();
        sessionStorage.clear();
    });

    // ---- Scene 01: cold visit. i18next should auto-detect navigator language ----
    await page.goto('/');
    await page.waitForURL('**/login');
    await page.waitForTimeout(2500); // hold for human viewer to read

    // ---- Scene 02: type email (per-char typing for visual effect) ----
    const emailInput = page.getByTestId('login-email');
    await emailInput.click();
    await page.waitForTimeout(400);
    await emailInput.pressSequentially('admin@local.test', { delay: 80 });
    await page.waitForTimeout(1200);

    // ---- Scene 03: type password ----
    const passwordInput = page.getByTestId('login-password');
    await passwordInput.click();
    await page.waitForTimeout(400);
    await passwordInput.pressSequentially('admin12345', { delay: 80 });
    await page.waitForTimeout(1500);

    // ---- Scene 04 → 05: submit and observe Today view ----
    await page.getByTestId('login-submit').click();
    await page.waitForURL('**/today');
    await page.waitForTimeout(3500); // hold so viewer can read 「今天,」/「今天完成」
});
