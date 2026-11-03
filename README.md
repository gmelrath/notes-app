# notes-app

**Campfire** is a personal iPhone and iPad app for saving links, notes and files from the share sheet. Share a post or article, then send it to a Notion reading list or to your email inbox. Every capture is logged and synced between your devices through iCloud, so you can see whether you've already saved something.

## What it does

- **Share card:** tap Share in any app (Safari, X, LinkedIn…), then **Campfire**. The card shows the page title (editable), an optional note, and **Notion** / **Email** buttons.
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
| 7 | Polish: app icon, design pass, real-world testing | Next |

## Project layout

```
App/             Main app: history, detail and settings screens
ShareExtension/  The share card
Shared/          Code used by both: capture model, history store, iCloud sync, link metadata, sending
Config/          Info.plist and entitlements
```

The app and the share card share storage through the App Group `group.com.gregmelrath.Capture`. The app was first called Capture, and its bundle IDs and App Group keep that name so the history already on the phone carries over.

## iCloud sync

The history is mirrored to the private iCloud database of the container `iCloud.com.gregmelrath.Campfire`, in a zone called History, one `Capture` record per entry. Each record stores the entry as JSON, so adding fields needs no iCloud schema change.

- Each device keeps its own copy in `captures.json`, so the app and share card work offline. Changes queue up and upload when there's a connection.
- The app syncs when it opens, after sending or deleting, and when iCloud signals that another device changed something. The share card syncs when it opens, so its duplicate warning includes links sent from the other device.
- The email address in Settings syncs through iCloud key-value storage.
- Builds installed from Xcode use iCloud's **Development** environment. Before distributing through TestFlight, deploy the schema to Production in the [CloudKit Console](https://icloud.developer.apple.com).

## Build and install

You need Xcode and an Apple Developer Program membership, which keeps the app working for a year between installs. A free Apple ID also works, but the app then stops opening after 7 days and has to be reinstalled.

1. Open `Campfire.xcodeproj`.
2. For both the **Campfire** and **ShareExtension** targets, go to **Signing & Capabilities** and choose your team.
3. Plug your iPhone directly into the Mac (not through a hub), and turn on **Settings → Privacy & Security → Developer Mode**.
4. Choose your iPhone as the run destination and press **▶ Run**.
5. The first time, trust the developer on the phone: **Settings → General → VPN & Device Management**.

## Keys

Private keys go in `Config/Secrets.xcconfig`, which git ignores. To create it, copy `Config/Secrets.example.xcconfig` and fill it in. Keys are built into the app, so rebuild after changing them.

### Notion

1. At [notion.so/profile/integrations](https://www.notion.so/profile/integrations), create an **internal** integration (API token) called Campfire, and copy its secret into `NOTION_TOKEN`.
2. In Notion, open the page that contains the database, then go to **••• → Connections** and add **Campfire**.

The target database is set by `NOTION_DATA_SOURCE_ID` in `Config/Campfire.xcconfig`. Each capture becomes a row with:

| Column | Value |
|---|---|
| Title | The page title, as edited on the card |
| URL | The shared link |
| Summary | The page's own description, if it has one |

Notes written in the app follow slightly different rules. With a link, your note goes in Summary instead of the page's description. Without a link, the note's first line is the Title, the rest is the Summary, and URL is left empty.

### Email

Email is sent through [Resend](https://resend.com).

1. Sign up with the address you'll send captures to, and enter that address in the app's Settings. Resend's shared sender (`onboarding@resend.dev`) can only deliver to the account owner's address.
2. Create an API key with **Sending access**, and copy it into `RESEND_API_KEY`.

Each email uses the page title as its subject. The body has your note, the link, the page description and any shared text. Shared files are attached, up to 25 MB in total. If an email with files fails, copies of the files are kept on the phone so it can be retried from History. They're removed once it sends, or when you delete the entry.
