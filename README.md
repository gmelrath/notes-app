# notes-app

**Capture** is a personal iPhone app for saving links, notes and files from the share sheet. Share a post or article, then send it to a Notion reading list or to your email inbox. Every capture is logged on the phone, so you can see whether you've already saved something.

## What it does

- **Share card:** tap Share in any app (Safari, X, LinkedIn…), then **Capture**. The card shows the page title (editable), an optional note, and **Notion** / **Email** buttons.
- **Duplicate warning:** if you've captured a link before, the card says when and where it went. Tracking codes like `utm_*` are ignored when comparing links.
- **History:** the app lists every capture with search, a detail view, swipe to delete, and retry for failed sends.
- **Settings:** the email address that captures are sent to.

## Status

| Phase | | |
|---|---|---|
| 1 | Share card in the share sheet | Done |
| 2 | On-phone history, duplicate warning, Settings | Done |
| 3 | Send to Notion ("Things to Read…" database) | Next |
| 4 | Send by email (with file attachments) | Planned |
| 5 | Polish: app icon, design pass, real-world testing | Planned |

## Project layout

```
App/             Main app: history, detail and settings screens
ShareExtension/  The share card
Shared/          Code used by both: capture model, history store, link metadata, sending
Config/          Info.plist and entitlements
```

The app and the share card share storage through the App Group `group.com.gregmelrath.Capture`.

## Build and install

You need Xcode and an Apple ID. A free account works, but the app stops opening after 7 days and has to be reinstalled.

1. Open `Capture.xcodeproj`.
2. For both the **Capture** and **ShareExtension** targets, go to **Signing & Capabilities** and choose your team.
3. Plug your iPhone directly into the Mac (not through a hub), and turn on **Settings → Privacy & Security → Developer Mode**.
4. Choose your iPhone as the run destination and press **▶ Run**.
5. The first time, trust the developer on the phone: **Settings → General → VPN & Device Management**.

API keys for Notion and email (phases 3 and 4) go in `Config/Secrets.xcconfig`, which git ignores.
