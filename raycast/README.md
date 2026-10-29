# Notch Monster for Raycast

This local companion receives the exact files you feed Notch Monster. Choose **Open With**, Quick Look, Open, Show in Finder, Copy File, Copy Path, or Move to Trash from Raycast's action panel. Multiple files appear together. No search indexing or home-folder permission is needed, and sending a file does not move or delete it.

## One-time setup

Install [Raycast](https://www.raycast.com/) and [Node.js](https://nodejs.org/) if needed. In Notch Monster Settings, select **Send to Raycast**, then click **Raycast setup instructions…**. The app copies this companion into your writable `~/Library/Application Support/Notch Monster/Raycast` folder and opens these instructions there. It preserves installed dependencies when refreshing the source files.

Open Terminal and run:

```sh
cd "$HOME/Library/Application Support/Notch Monster/Raycast"
npm ci
npm run dev
```

Raycast's official development command installs the extension locally. After **Caught Files** appears in Raycast, press Control-C in Terminal; the installed command remains available. Nothing is published to the Raycast Store.

Keep that Application Support folder in place; the local extension uses it independently of the app bundle. Do not run npm inside `Notch Monster.app`. If you are developing from source, you can instead run the npm commands from the repository's `raycast` folder.

In **Notch Monster → Settings**, change **When I feed it files** to **Send to Raycast**. Drop one or more files near the notch, then choose an action in Raycast with Return or Command-K. Windows continue to close normally when that setting is enabled.

Raycast may ask you to confirm opening the command from Notch Monster. If it reports the command is missing, repeat the setup above. Notch Monster never falls back to Trash when Raycast is selected.

Developer checks: `npm run typecheck` and `npm run build`.
