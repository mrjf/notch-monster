# Notch Monster website

Live: https://notchmonster.com (also https://www.notchmonster.com).

A buildless static desktop demo in `dist/`, deployed as Cloudflare Worker static assets. `wrangler.jsonc` owns both custom domains. DreamHost remains the registrar; Cloudflare nameservers are keaton.ns.cloudflare.com and kristina.ns.cloudflare.com.

Sounds are off by default. The menu bar speaker mutes or unmutes the demo, and the Dock gear opens sound settings. Fuzzy, Rubber, and Arcade use the app's bundled Earshot cues, with Preview and saved sound preferences. Recipes and signal audits are in `../sound-design/`.

Move an empty pointer just below the notch's center for a short wave. Settings also offers **Bat the cursor away**, off by default with the choice saved. The website animates a demo cursor being swatted; browsers cannot reposition the system pointer. The native app can send the actual pointer flying.

Preview from this directory: `python3 -m http.server 4173 --bind 127.0.0.1 --directory dist`.

Deploy from this directory: `wrangler deploy` with the authenticated Cloudflare account. Keep `dist/assets/Notch-Monster-0.1.11.dmg` current with the packaged native app. The DMG opens a styled drag-to-Applications window with first-launch security instructions. The app inside is development signed, not notarized.

Wallpaper and historical icon provenance is in `ASSET-SOURCES.md`. The demo accepts only its own pretend items; it never reads or deletes real dropped files. Safari's title bar and the three files support pointer dragging and keyboard Enter. Dock Safari restores the window; Trash restores pretend files; Reset Desktop restores everything.

Verified: real pointer drop/withdrawal, all four items, window folding, keyboard, Dock restoration, no scroll overflow at 1280×800 and 390×667, no browser console errors, HTTPS on both domains, and public ZIP hash/signature.

Run `npm test` for attachment and drop regressions. The drop tests execute the production pointer handlers with a controlled clock: quick drops, stationary holds, final mouse-up wobble, visible hand contact during retreat, and deliberate withdrawal. Once an offer is accepted, releasing completes the feed. Only sustained, observed outward pointer movement can call it off; a pause, animation timing, or final mouse-up coordinate cannot revoke the grab. Released-button capture loss also completes an accepted drop, while pointer cancellation never feeds it.

Arm rendering regression: serve the `website/` directory and open `tests/arm-occlusion.html`. It draws eight shallow-reach/retraction poses with the production renderer and checks the actual canvas pixels for leaks behind the notch. All eight must pass, including fully withdrawn hands with no visible pixels. This fixture is outside the deployed `dist/` directory.

Layout regression: with the same server, open `tests/stable-layout.html`. It paints the production page before loading its interaction module, checks every startup frame for movement, and verifies centering at desktop and mobile sizes. All 11 checks must pass. Home positions are CSS-owned; dragging freezes the current rectangle into pixel coordinates, and resizing preserves moved or consumed items.
