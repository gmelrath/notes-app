# notes-app

**Stowaway** is a personal iPhone and iPad app for saving links, notes and files from the share sheet. Share a post or article, then send it to a Notion reading list or to your email inbox. Every capture is logged and synced between your devices through iCloud, so you can see whether you've already saved something.

## What it does

- **Share card:** tap Share in any app (Safari, X, LinkedIn…), then **Stowaway**. The card shows the page title (editable), an optional note, and **Notion** / **Email** buttons.
- **Duplicate warning:** if you've captured a link before, on either device, the card says when and where it went. Tracking codes like `utm_*` are ignored when comparing links.
- **Write a note:** the app opens on a compose screen. Type a note, and optionally add a link with **Paste**, then send it to Notion or email. Without a link, the note's first line becomes the title.
- **Sent:** the archive-box button lists every capture with search, a detail view, swipe to delete, and retry for failed sends.
- **Settings:** the gear button sets the email address that captures are sent to. It syncs between devices.
- **iPad:** works in any orientation and with Split View. With a hardware keyboard, ⌘↩ sends to Notion and ⇧⌘↩ sends by email.

## Status

| Phase | | |
|---|---|---|
| 1 | Share card in the share sheet | Done |
| 2 | On-phone history, duplicate warning, Settings | Done |
| 3 | Send to Notion ("Things to Read…" database) | Done |
| 4 | Send by email (with file attachments) | Done |
| 5 | Paid developer account, renamed to Campfire | Done |
| 6 | iPad support, history shared between devices through iCloud | Done |
| 7 | App icon and accent colour; real-world testing continues | Done |
| — | Renamed to Stowaway (NMB-31). The Keychain name and iCloud container keep "Campfire" so saved keys and history carry over. | Done |

## Project layout

```
App/             Main app: history, detail and settings screens
ShareExtension/  The share card
Shared/          Code used by both: capture model, history store, iCloud sync, link metadata, sending
Config/          Info.plist and entitlements
Design/          Source artwork for the app icon, and the script that prepares it
Tests/           Automated tests of the shared logic (see Tests below)
```

**Adding a screen:** build it on `Page` (in `App/Page.swift`), as Stowaway, Sent, Details and Settings do. It draws the shared header inside the iPad content column, hides iOS's own top bar, and turns swiping back from the left edge on for that screen. Then add it to `Screen` (in `App/Screen.swift`) and open it with `NavigationLink(value: Screen.…)`. Never use `NavigationLink { SomeView() }`: mixing the two kinds of link makes SwiftUI push screens twice.

The app and the share card share storage through the App Group `group.com.gregmelrath.Capture`. The app was first called Capture, and its bundle IDs and App Group keep that name so the history already on the phone carries over.

## App icon

The icon is Sneaky the fox, drawn in `Design/icon.svg` (the "full-box-v2" artwork). The app icon itself is `App/AppIcon.icon`, an Icon Composer file you can open in Icon Composer (it comes with Xcode). It has two parts:

- **Background:** the navy, a colour set in `AppIcon.icon/icon.json`.
- **Fox and box:** `AppIcon.icon/Assets/fox.png`, cut from the SVG with its background left out.

iOS 26 and later draw the Default, Dark, Tinted and Clear Home Screen looks from those, with the Liquid Glass edge. Xcode makes the plain images iOS 18 needs from the same file.

To change the artwork, replace `Design/icon.svg` and run `swift Design/make-icon.swift` from the repo root to remake `fox.png`. The script removes the background by leaving out the full-size rectangle the SVG draws first, so a new SVG needs to start the same way. If the background colour changes, update it in Icon Composer too.

Buttons and links use the `AccentColor` in `Shared/Assets.xcassets`.

## iCloud sync

The history is mirrored to the private iCloud database of the container `iCloud.com.gregmelrath.Campfire`, in a zone called History, one `Capture` record per entry. Each record stores the entry as JSON, so adding fields needs no iCloud schema change.

- Each device keeps its own copy in `captures.json`, so the app and share card work offline. Changes queue up and upload when there's a connection.
- The app syncs when it opens, after sending or deleting, and when iCloud signals that another device changed something. The share card syncs when it opens, so its duplicate warning includes links sent from the other device.
- The email address in Settings syncs as a `Settings` record in the same zone. The most recent change wins.
- Builds installed from Xcode use iCloud's **Development** environment. Before distributing through TestFlight, deploy the schema to Production in the [CloudKit Console](https://icloud.developer.apple.com).

## Build and install

You need Xcode and an Apple Developer Program membership, which keeps the app working for a year between installs. A free Apple ID also works, but the app then stops opening after 7 days and has to be reinstalled.

1. Open `Stowaway.xcodeproj`.
2. For both the **Stowaway** and **ShareExtension** targets, go to **Signing & Capabilities** and choose your team.
3. Plug your iPhone directly into the Mac (not through a hub), and turn on **Settings → Privacy & Security → Developer Mode**.
4. Choose your iPhone as the run destination and press **▶ Run**.
5. The first time, trust the developer on the phone: **Settings → General → VPN & Device Management**.

## Tests

The `Tests` folder holds automated tests of the app's core logic: duplicate matching, finding links, link titles and post detection, Notion formatting and length limits, notes, destination rules, and the history file and iCloud merging. They use Swift Testing and run in the iPhone simulator, never on a device, with no network.

Run them with **⌘U** in Xcode, or:

```bash
xcodebuild test -project Stowaway.xcodeproj -scheme Stowaway -destination 'platform=iOS Simulator,name=iPhone 17'
```

Anything that needs the internet or a real account (sending to Notion or Resend, Apple's link previews, iCloud) is still checked by hand on a device.

## Keys

The Notion and Resend keys are never part of the app or this repository. Paste them into the app's **Settings → Keys** once. The app keeps them in the device's Keychain, shares them with the share card, and iCloud Keychain carries them to your other devices. Paste a new key there to replace one; no rebuild is needed.

### Notion

1. At [notion.so/profile/integrations](https://www.notion.so/profile/integrations), create an **internal** integration (API token) called Stowaway, and paste its secret into **Settings → Keys → Notion key**.
2. In Notion, open the page that contains the database, then go to **••• → Connections** and add **Stowaway**.

The target database is set by `NOTION_DATA_SOURCE_ID` in `Config/Stowaway.xcconfig`. Each capture becomes a row with:

| Column | Value |
|---|---|
| Title | The page title, as edited on the card |
| URL | The shared link |
| Summary | The page's own description, if it has one |

Notes written in the app follow slightly different rules. With a link, your note goes in Summary instead of the page's description. Without a link, the note's first line is the Title, the rest is the Summary, and URL is left empty.

### Email

Email is sent through [Resend](https://resend.com).

1. Sign up with the address you'll send captures to, and enter that address in the app's Settings. Resend's shared sender (`onboarding@resend.dev`) can only deliver to the account owner's address.
2. Create an API key with **Sending access**, and paste it into **Settings → Keys → Resend key**.

Each email uses the page title as its subject. The body has your note, the link, the page description and any shared text. Shared files are attached, up to 25 MB in total. If an email with files fails, copies of the files are kept on the phone so it can be retried from History. They're removed once it sends, or when you delete the entry.
