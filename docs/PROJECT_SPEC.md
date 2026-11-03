# SlotBook: Project Specification (for backend selection)

A complete description of SlotBook as of **2026-10-27** (branch `globe`): what it does, how its data is shaped, how it is
built and shipped per client, and where it is going. Its purpose is to let anyone (a person or an AI) choose and design a
backend without reading the code. Section 11 turns all of it into backend requirements; section 13 lists the questions
that still need an answer from the owner.

Sources of truth: the code under `lib/`, `CLAUDE.md` (working rules) and `docs/EXPANSION_PLAN.md` (agreed roadmap).
If this file disagrees with the code, the code wins.

---

## Contents

1. [Summary](#1-summary)
2. [Scope](#2-scope)
3. [Features](#3-features)
4. [Data model](#4-data-model)
5. [Business rules (invariants)](#5-business-rules-invariants)
6. [Architecture](#6-architecture)
7. [Multi-client model (flavors)](#7-multi-client-model-flavors)
8. [Business profiles](#8-business-profiles)
9. [Current storage and remote config](#9-current-storage-and-remote-config)
10. [Roadmap](#10-roadmap)
11. [Backend requirements](#11-backend-requirements)
12. [Backend design notes and options](#12-backend-design-notes-and-options)
13. [Open questions for the owner](#13-open-questions-for-the-owner)

---

## 1. Summary

| | |
|---|---|
| **Product** | SlotBook: a booking and payment **ledger** for businesses that rent out time on a resource. |
| **Started as** | An app for indoor cricket and padel arena owners. |
| **Now** | Generalised into "core + business profile + client": sports venues, space rental (rooms, studios, workspaces), event halls, vehicle rental. |
| **User** | The business **owner** (or their front-desk person) on **one phone**. Customers never use the app. |
| **Core job** | Book a resource for a time range without double booking, record advance / discount / balance, share a receipt on WhatsApp. |
| **Today's storage** | 100% on-device and offline: Hive CE (bookings), SharedPreferences (settings). No login, no server. |
| **Only network call** | A GitHub Gist read for the remote trial / licence switch. |
| **Distribution** | One white-labelled app **per client**, built from one codebase via Flutter flavors (flavor name = client id). |
| **Company** | DevCat Studios. Market today: Pakistan (currency `Rs`, country code `92`, UTC+5, no DST). |
| **Stack** | Flutter 3.38 / Dart 3.10, GetX (state, routing, DI), Hive CE, SharedPreferences, `http`, `share_plus`, `qr_flutter`, `url_launcher`. |
| **Platforms** | Android (primary), iOS (configured, not yet built on a Mac). Portrait phones only. Web/desktop folders are starter leftovers. |
| **Quality** | ~177 unit + widget tests; pure rules are separated from UI and unit-tested. |

---

## 2. Scope

### 2.1 In scope today

- Single business, single device, single operator (no accounts, no roles).
- Bookings of one continuous time range on one resource, up to 24 hours, possibly crossing midnight.
- Payment tracking as **advance + one-step settlement** ("Mark Paid"), optional discount. No payment gateway.
- Receipts (image + text), shared through the phone's share sheet / WhatsApp; customer contact by call, SMS, WhatsApp.
- Dashboard stats, a pending-dues list, a calendar, search and filters.
- Per-client branding, wording, time rules, pricing mode and optional features, all compiled in.
- Remote enable / disable / dated trial per client.

### 2.2 Explicitly out of scope (decided, not forgotten)

| Not supported | Why / status |
|---|---|
| Instalments (more than advance + balance) | Decision D4. Overruns are handled by editing the amount received and writing a note. |
| Editing past time | Past time is never edited. |
| Customer-facing app / online booking by customers | Not planned yet (see open questions). |
| Staff calendars, staff accounts | Only if customers repeatedly ask. |
| Bookings longer than 24 h (multi-day rentals, hotel stays) | Max one day per booking; storage allows end up to 48 h on the timeline. |
| Setup wizard / owner choosing a business type | Developer picks the profile per client (D1). Self-service is a future goal (D5). |
| Backup / export | Postponed by the owner. Data is lost if the phone is lost: a strong reason for a backend. |
| In-app editing of resources (courts) | Resources come from compiled config. Planned in Phase 6. |
| Online payments, accounting exports, SMS gateway | Not planned. |

### 2.3 Starter leftovers (present, unused)

The app is built on an in-house GetX starter. These parts exist for a future online version and are **not** wired into the app:
`data/providers` (`ApiProvider`, endpoints, connectivity), login and dashboard screens, `UserStore` (profile, user id, token),
`UrlsStore` (API base URL), an AES-encrypted Hive **response cache**, developer-mode services, and a no-internet dialog that
is intentionally commented out. `AppClientConfig.baseUrl / stageBaseUrl / localBaseUrl` are empty placeholders.
A backend integration can reuse this layer (HTTP client, token storage, encrypted cache) or replace it.

---

## 3. Features

Industry words below (Court, Ground, Player, Fee…) come from the client's business profile `Terms`; see section 8.

### 3.1 App shell

- Splash (SlotBook brand), then one route `/slotbook` with an `IndexedStack` of five tabs; each tab keeps its scroll and filters.
- Bottom navigation: **Home, Bookings, + (New booking), Pending, Calendar**. The Pending tab shows a dot while any balance is due.
- Header: client logo (or monogram) and business name, today's date.
- Drawer: client logo + name + "`<subject>` Management", **Settings & Preferences**, **About Us & Dev Details**,
  **Contact Support** (WhatsApp / call / email the developer), a **trial notice** ("N days remaining") while a dated trial runs, app version.
- A per-minute tick (and app resume) refreshes everything time-based: slots turn "past", "today" rolls at midnight,
  and the trial switch is re-checked.
- Light and dark theme (dark by default); every animation honours the OS reduce-motion setting.
- Android back: closes drawer, else returns to Home, else exits.

### 3.2 Home (dashboard)

- Filter chips: **All `<Resources>`** or one resource type.
- Four stat tiles (cancelled bookings excluded):
  | Tile | Formula |
  |---|---|
  | Total Slots | number of non-cancelled bookings |
  | Pending Dues | Σ `balanceDue`, with a count of bookings that have a balance |
  | Collected | Σ `amountCollected` |
  | Total Value | Σ `payable` (fee after discount) |
- **Upcoming & Active Slots**: the next 4 non-cancelled bookings from today on, soonest first.
- Stats are computed on the fly from the full booking list every time (no stored aggregates).

### 3.3 New / Edit booking form

| Step | Behaviour |
|---|---|
| Resource type | Cards for each **enabled** type, showing its current hourly rate (hourly pricing). |
| Resource | Dropdown of that type's resources; optional description under each name. |
| Date | Strip of the next 7 days + "Custom Date" picker (today up to 2 years ahead). No past dates. |
| Time (free start) | The day is split into Night / Morning / Afternoon / Evening (6 h each). Start-time chips every `step` minutes show **available / selected / booked / past**. Periods with no opening hours are hidden; closed hours are greyed on a day bar. |
| Duration | +/- in `step` minutes between `minDuration` and the room before the next booking, closing time or `maxDuration`. Optional **Full day** (24 h) shortcut. |
| Time (sessions) | If the policy has fixed sessions (e.g. Lunch / Dinner / Full Day), session cards replace chips and duration. |
| Customer | Name (required), phone (required, 10–11 digits), email (optional, validated), notes (≤ 120 chars). |
| Price | Hourly: `minutes × rate / 60`, rounded. Manual: a required typed price. |
| Discount | Optional field (only when the `discount` feature is on), 0..fee. |
| Advance | Amount received now, auto-capped to the payable amount. Shows remaining balance live. |
| Submit | Validates everything again in the service, saves, shows a toast with the new id, opens the **invoice**; closing it returns to Home. Double-tap safe. |

- **Edit**: only for non-cancelled bookings dated today or later. The form is prefilled; the advance field becomes
  **Amount Received** (= money collected so far). Saving clears any earlier "Mark Paid" and re-evaluates it.
  The booking keeps its original pricing mode and its agreed hourly rate (if the resource type is unchanged), and may keep
  time slots that have already started or that no longer fit a changed policy.
- **Repeat**: copies customer, resource type and resource to **today**; pre-selects the same time if it is still free;
  copies a manual price; never copies the discount.
- A half-filled new booking survives switching tabs. "+" always leaves edit mode.
- The trial switch is checked before opening the form and again before saving.

### 3.4 Bookings tab

- Search by customer name, phone or booking reference.
- Filters: resource type, date range, timeline **Upcoming (default) / Past / All**.
- Order: upcoming soonest first; past/all most recent first.
- Each card: status badge (Paid / Pending / Cancelled), customer, resource, date, slots, money, cancel reason
  ("Advance returned / kept"). Actions: **Invoice**, **Repeat**, **Edit** (if editable), **Cancel** (if not cancelled; past bookings can be cancelled too).

### 3.5 Pending tab

- Total balance due across all bookings with `balanceDue > 0`, and the list of them.
- Each row: customer, resource, date, phone, amount due; actions **Invoice** and **Mark Paid**.
- **Mark Paid** asks for confirmation ("Record Rs X received from … ?"), then sets `balanceSettledAt = now`.

### 3.6 Calendar tab

- Month grid with one coloured dot per resource type booked that day (cancelled excluded), in config order.
- Month navigation (animated in the direction of travel) and a **Today** button.
- Selected day lists its bookings.

### 3.7 Invoice / receipt

- Bottom sheet that updates live (e.g. after Mark Paid).
- Content: business logo and name, address and phone, status badge, `#TRF-1001`, "Official `<subject>` Booking Receipt",
  customer (name, phone, email), date, slots, resource, duration (× rate for hourly), fee, discount line (feature on and > 0),
  total, advance paid, balance paid with date, remaining balance.
- **QR entry pass** (feature `entryPass`): payload `SLOTBOOK|<id>|<yyyy-mm-dd>|<resourceId>|<start>-<end>,...`
  and the caption from `Terms.passHint`. Nothing scans it yet (no verification app or server).
- Actions:
  - **Share via WhatsApp**: renders the receipt widget to a PNG and opens the system share sheet. No server involved.
  - **Copy Text**: copies a plain-text invoice (`InvoiceText.plain`) to the clipboard. A WhatsApp-markdown version (`InvoiceText.whatsApp`) also exists.
  - **Contact**: call, SMS, or WhatsApp (`wa.me/<number>`) the customer. Local numbers are converted with the client's country code (`03001234567` → `923001234567`).
  - **Mark Paid** (while a balance is due).

### 3.8 Cancel booking

- Dialog requires a **reason** and a choice: **advance returned** or **kept**. Stores `cancelledAt`, reason, flag.
- A cancelled booking frees its time, can't be edited, still shows in lists and receipts.

### 3.9 Settings (drawer)

- Theme: light / dark (applies instantly; device-level).
- Currency symbol (default from client config, e.g. `Rs`).
- Hourly rate per enabled resource type (1..1,000,000; hidden under manual pricing). Saved on "Save & Close".
  Changing a rate never changes existing bookings (each stores its own rate).

### 3.10 Remote trial / licence switch

Detailed in section 9.3. In short: a GitHub Gist holds one entry per client; the app can be enabled, disabled now,
or disabled after a date (with a drawer countdown). A blocking, non-dismissable dialog appears after the splash.

### 3.11 About and support

- About: SlotBook brand, tagline built from the client's resource types, version/build, "Licensed to `<client>`", developer website, open-source licences.
- Support: WhatsApp, call, email to DevCat Studios (constants in `AppStrings`).

---

## 4. Data model

All models are pure Dart (no Hive/Firebase types). Money is an **int in whole currency units** (no paisa/cents).
Times are **local wall-clock** values; there is no time zone field anywhere today.

### 4.1 Entity overview

```
ClientConfig (compiled, 1 per app build)
 ├─ profile: BusinessProfile ── Terms, BookingPolicy, PricingMode, Features
 ├─ overrides: policy?, pricing?, features?
 └─ resourceTypes: [ResourceType]
                     └─ resources: [Resource]

Settings (device prefs): currencySymbol, hourlyRate per resourceType id, theme
Booking (Hive, one record per booking) ──> resourceType.id, resource.id  (by id, no foreign keys)
AppAccess (remote Gist, cached in prefs)
```

There is **no separate Customer entity**: name, phone and email are copied onto each booking. There is no User, Staff,
Payment or AuditLog entity. A backend is the natural moment to decide whether to add some of these (section 13).

### 4.2 Booking (the only persisted business record)

| Field | Type | Stored JSON key | Rules |
|---|---|---|---|
| `id` | String | `id` | `TRF-1001`, `TRF-1002`… sequential per device. Display reference **and** current primary key. |
| `customerName` | String | `customerName` | Required, trimmed. |
| `phone` | String | `phone` | Digits only, 10–11 digits. |
| `email` | String | `email` | `''` when not given. |
| `notes` | String | `notes` | ≤ 120 chars. Also where overrun explanations go. |
| `resourceType` | ResourceType | **`sport`** (its id) | Legacy key name kept on purpose. |
| `resourceId` | String | **`courtId`** | Legacy key name kept on purpose. |
| `date` | Date | `date` | `"yyyy-mm-dd"`, local calendar day of the **start**. |
| `slots` | List&lt;TimeRange&gt; | `slots` | `[{start, end}]` minutes from that day's midnight; sorted; today always exactly one range. |
| `pricing` | enum | `pricing` | `hourly` \| `manual` (v3+; missing = hourly). |
| `hourlyRate` | int | `hourlyRate` | Rate frozen at booking time; 0 for manual. |
| `totalFee` | int | `totalFee` | Price before discount. |
| `discount` | int | `discount` | 0..totalFee (v2+; missing = 0). |
| `advancePaid` | int | `advancePaid` | Money received at booking / last edit; 0..payable. |
| `balanceSettledAt` | DateTime? | `balanceSettledAt` | Set by Mark Paid. ISO-8601 local. |
| `cancelledAt` | DateTime? | `cancelledAt` | Set on cancel. |
| `cancelReason` | String | `cancelReason` | Required to cancel. |
| `advanceReturned` | bool | `advanceReturned` | Meaningful only when cancelled. |
| `createdAt` | DateTime | `createdAt` | ISO-8601 local, no offset. |
| `updatedAt` | DateTime | `updatedAt` | Bumped on every change (sync-ready). |
| — | int | `v` | Schema version, currently **3**. |

**Derived, never stored:** `payable = totalFee − discount`; `isSettled = balanceSettledAt != null || advancePaid ≥ payable`;
`balanceDue = (cancelled or settled) ? 0 : payable − advancePaid`;
`amountCollected = cancelled ? (advanceReturned ? 0 : advancePaid) : (settled ? payable : advancePaid)`;
`status = cancelled | pending (balanceDue > 0) | paid`; `totalMinutes`; `startsAt`.

**Example stored record (v3):**

```json
{
  "v": 3,
  "id": "TRF-1042",
  "customerName": "Ali Khan",
  "phone": "03001234567",
  "email": "",
  "notes": "Brought own balls",
  "sport": "cricket",
  "courtId": "cricket-2",
  "date": "2026-10-27",
  "slots": [{ "start": 1350, "end": 1530 }],
  "pricing": "hourly",
  "hourlyRate": 3500,
  "totalFee": 10500,
  "discount": 500,
  "advancePaid": 3000,
  "balanceSettledAt": null,
  "cancelledAt": null,
  "cancelReason": "",
  "advanceReturned": false,
  "createdAt": "2026-10-25T18:04:11.532",
  "updatedAt": "2026-10-25T18:04:11.532"
}
```

(`1350–1530` = 10:30 PM to 1:30 AM next day; the record lives on 27 Oct.)

**Schema history:** v1 original; v2 added `discount` (missing → 0); v3 added `pricing` (missing → hourly).
Every bump must load old records in `fromJson` and has a migration test on a stored sample. Unreadable records are
skipped (logged) and left on disk, never crash the app.

**Lifecycle:** records are **never deleted**: they are created, edited (only while upcoming and active), marked paid, or cancelled.

```
create ──> active(pending|paid) ──edit──> active
                 │  └─ markPaid ──> paid (until next edit re-evaluates)
                 └─ cancel(reason, advanceReturned) ──> cancelled (terminal)
```

### 4.3 TimeRange

`{ startMinute, endMinute }`, minutes from the booking day's midnight. `0 ≤ start < end ≤ 2880` (end may reach the
next midnight). Half-open: `[start, end)`, so 9–10 and 10–11 don't overlap. Labels like `11PM - 1AM (next day)` are
display only; logic never uses strings.

### 4.4 ResourceType and Resource (catalogue, compiled into each client today)

| ResourceType field | Meaning |
|---|---|
| `id` | Stable key stored in bookings and prefs (`cricket`, `room`, `sedan`). Never changes. |
| `label` / `shortLabel` | "Indoor Cricket" / "Cricket". |
| `icon` | Flutter `IconData` (to become an icon key in Phase 6, so it can be stored as data). |
| `tone` | Colour family: `emerald`, `blue`, `violet`, `orange`. |
| `defaultRate` | Hourly rate until changed in Settings. |
| `emoji` | Used in shared receipts. |
| `resources` | List of `Resource`. |
| `enabled` | `false` hides it from forms, filters and Settings; old bookings still show. |

| Resource field | Meaning |
|---|---|
| `id` | Stable key stored in bookings (`cricket-1`, `padel-a`). Unique across the client. Never changes. |
| `name` | Shown everywhere. |
| `description` | Optional detail shown only in the booking form's picker. |

Unknown ids (removed from config) resolve to placeholders so old bookings keep rendering.

### 4.5 Business configuration types

| Type | Fields |
|---|---|
| `BusinessProfile` | `id` (`sports_venue`, `space_rental`, `event_venue`, `vehicle_rental`), `terms`, `policy`, `pricing`, `features` |
| `Terms` | `subject`, `resource`, `resources`, `resourceType`, `customer`, `fee`, `place`, `passHint`, `receiptThanks`, `cancelReasonHint` (strings) |
| `BookingPolicy` | `step` (15/30/60), `minDuration`, `maxDuration` (≤ 1440), `defaultDuration`, `openHours` (TimeRange or null = 24 h; may pass midnight), `sessions` (list of `{label, TimeRange}`), `offersFullDay` |
| `PricingMode` | `hourly` \| `manual` |
| `Features` | `discount` (bool), `entryPass` (bool) |
| `ClientConfig` | `id`, `name`, `tagline?`, `logoAsset?`, `address?`, `phone?`, `profile`, `resourceTypes`, `policy?`, `pricing?`, `currency` (default `Rs`), `countryCode` (default `92`), `features?` |

Effective value = **client override → profile → core default**, then the owner's saved Settings (rates, currency) on top.
All of these are plain data on purpose (decision D5), so they can move to a database later.

### 4.6 Settings and device state (SharedPreferences)

| Key | Type | Scope | Meaning |
|---|---|---|---|
| `slotbook_currency_symbol` | String | business | Currency symbol shown on money. |
| `slotbook_<typeId>_hourly_rate` | int | business | Hourly rate per resource type. |
| `isDarkMode` | bool | device | Theme (default dark). |
| `app_access_config` | String | device | Last Gist body from GitHub (trial switch). |
| `app_access_latest_time` | int (ms) | device | Latest trusted time seen (defeats clock rewinds). |
| `ThemeColor`, `userPreferenceId`, `Profile`, `UserId`, `Token`, `ApiUrl`, `Url`, `dev_mode`, `ResponseCacheKey` | — | starter | Unused by SlotBook today. |

Note: business settings and device settings are currently mixed in the same store; separating them is a Phase 6 item.

### 4.7 Hive boxes

| Box | Key | Value |
|---|---|---|
| `bookings` | booking id (`TRF-1042`) | booking JSON map (above) |
| `bookings_meta` | `lastBookingNumber` | int counter (starts at 1000; skips ids already present) |
| starter response cache | — | encrypted API responses (unused) |

### 4.8 Indicative volumes (estimates, not measured)

Per client: 1–15 resources. A busy sports venue might take 30–80 bookings a day, about 10–30k bookings a year; an event hall
a few hundred a year. A booking record is roughly 0.5–1 KB of JSON, so one client is a few MB per year at most.
The client count is small today (4 demo clients) and is expected to grow to tens, maybe hundreds, of businesses.
Load is tiny; the hard parts are **correctness** (no double booking), **offline use**, **multi-tenancy** and **cost**.

---

## 5. Business rules (invariants)

A backend that accepts writes must enforce these (or at least the starred ones) itself, not trust the client.

1. ★ **No double booking** on the same resource. Overlap is half-open. Cancelled bookings free their time. A different
   resource at the same time is fine. Bookings crossing midnight conflict correctly with bookings on either date
   (`BookingRules.occupied` projects the previous and next day onto the timeline).
2. ★ **Time policy**: start and duration on `step` boundaries; `minDuration ≤ duration ≤ maxDuration ≤ 24 h`;
   inside `openHours` (if set); or exactly one of the `sessions` (if any). A booking starts on its booking date (start < 1440).
3. ★ **No booking in the past**: a slot is past once it has started. Exception: an edit may keep slots the booking already
   had (even if they started or the policy has changed since).
4. ★ **Edits** only on non-cancelled bookings dated today or later. Cancelled bookings are immutable.
5. ★ **Money**: `totalFee > 0`; hourly fee = `round(minutes × rate / 60)` with the rate frozen on the booking; manual =
   typed price (> 0). `0 ≤ discount ≤ totalFee` (only when the discount feature is on). Advance clamped to `0..payable`.
   Editing clears Mark Paid; it re-applies automatically if the amount received covers the payable.
6. **No instalments**: one advance figure plus one settlement. To charge more after the fact, the owner edits the amount
   (manual pricing can raise the price; hourly pricing can't exceed the fee: a known limit).
7. **Cancel** needs a reason and records whether the advance was returned.
8. **Mark Paid** requires confirmation in the UI and is idempotent in the service.
9. ★ **Ids never change**: client id, resource type id, resource id. Stored JSON keeps `sport` / `courtId`.
10. **Pricing mode is per booking**: changing a client's mode or rates never re-prices existing bookings.
11. **Never branch on business type or client id**: differences are values (config), behaviours (sealed strategy classes)
    or flags (`Features`). A backend should follow the same rule: per-tenant config, not per-tenant code.
12. **Calendar days are local**: never derive a booking's day from UTC (in UTC+5, local midnight is the previous day in UTC).

---

## 6. Architecture

### 6.1 Layers

```
Presentation (GetX views + controllers, per tab)
      │  reads BookingService.bookings inside Obx, calls BookingActions
      ▼
BookingService (GetxService, single source of truth, validation via BookingRules)
      │  save to repository first, then update the in-memory RxList
      ▼
BookingRepository (interface) ── HiveBookingRepository (app) / InMemoryBookingRepository (tests)
      ▼
Hive box "bookings"
```

```dart
abstract class BookingRepository {
  Future<List<Booking>> loadAll();        // whole ledger loaded into memory at startup
  Future<void> save(Booking booking);     // insert or replace by id
  Future<String> nextId();                // next TRF-#### reference
}
```

- **One write refreshes every tab**: Home, Bookings, Pending and Calendar all derive their data from the same reactive list.
- **All validation lives in the service** (`BookingRules`, pure Dart). It throws `BookingException` with a user-safe message.
- **Time is injectable** (`clock:`), so tests use a fixed "now". Nothing calls `DateTime.now()` in rules or controllers.
- **Pure rule modules**: `BookingRules` (time, overlap, validation, phone/WhatsApp formatting, money clamps),
  `BookingStats` (dashboard), `InvoiceText` (receipt text, QR payload). These could be ported to the server, or shared if
  the backend is Dart.
- **Startup order** (`InitBindings`): StorageService (prefs) → starter services → AppAccessService → SettingsStore →
  Hive init → open repository → `BookingService.init()` (loads all bookings).

### 6.2 Folder map

```
lib/
├── main.dart                       # GetMaterialApp, themes
├── app/config/                     # AppClientConfig, AppStrings, AppCache keys, theme
├── app/config/business/            # BusinessProfile, Terms, Features; profiles.dart (4 profiles)
├── app/config/clients/             # ClientConfig + one file per client
├── app/service/getx_service/       # BookingService, AppAccessService, starter services
├── app/service/service_handler.dart/ # SettingsStore, ThemeStore, CacheField (prefs)
├── data/models/                    # Booking, TimeRange, ResourceType/Resource, BookingPolicy, PricingMode, AppAccess
├── data/rules/                     # BookingRules, BookingStats, InvoiceText
├── data/repositories/booking/      # BookingRepository + Hive + in-memory
└── presentation/slotbook/             # shell, home, booking_form, bookings, pending, calendar, invoice, dialogs, widgets
tool/clients.dart                   # add a client / declare assets / iOS icon
scripts/build.(bat|sh)              # release build per client into dist/
```

### 6.3 Readiness for a backend (already done)

| Rule | Status |
|---|---|
| Screens → services → repository interface; Hive is one implementation | done |
| Models are pure Dart, JSON-serialisable | done |
| Every record has `updatedAt`; records are cancelled, never deleted | done |
| Stored JSON is versioned (`v`) with migrations in `fromJson` | done |
| `TRF-####` is a display reference, not a global key; sync will add a random `uid` | agreed rule, `uid` not added yet |
| New record types get a random id | agreed rule |
| `Booking.fromJson` looks up global config (`ResourceType.byId`) | to fix in Phase 6 |
| Business settings separate from device settings | Phase 6 |

Agreed sync direction (from `EXPANSION_PLAN.md` §4): **local-first**. Hive stays what the UI reads; a synced repository
writes to Hive plus an **outbox**, and a worker pushes and pulls. `BookingService` and the screens don't change.

---

## 7. Multi-client model (flavors)

**One codebase, one separately installed and branded app per client.** The Flutter flavor name **is** the client id.

| Aspect | How it works |
|---|---|
| Selecting the client | `AppClientConfig.client = ClientConfig.forFlavor(appFlavor)`; compiled in, no copy steps. No flavor (tests) = `demo`; unknown flavor throws. |
| Client config | `lib/app/config/clients/<id>.dart`: name, tagline, address, phone, logo, profile, resource types and resources, currency, country code, optional policy / pricing / features overrides. |
| App identity | Android `applicationIdSuffix` / iOS bundle id: `com.devcatstudios.slotbook.<id>`. Launcher name is "SlotBook" for all. |
| Assets | `assets/clients/<id>/`, declared per flavor in pubspec, so a build ships only its own files. |
| Launcher icon | Optional per client (Android source set, iOS `AppIcon-<id>`). |
| Registration | `ClientConfig.all`, Android `build.gradle.kts`, iOS Podfile + Xcode configs + scheme, `.vscode/launch.json`. Done by `dart run tool/clients.dart add <id>`; a test fails if they drift. |
| Licence switch | One Gist with a `clients` map keyed by client id. |
| Build | `scripts\build.bat <id> apk` → `dist/SlotBook-<id>-<version>.apk`. |
| Distribution | Sideloaded APKs today (store URLs empty). Release builds still use the debug key. |

**Current clients:**

| id | Business | Profile | Notes |
|---|---|---|---|
| `demo` | Apex Arena, Islamabad | `sportsVenue` | Cricket (3 pitches), Padel (3 courts). |
| `demo_space` | The Loft Workspaces & Studio, Lahore | `spaceRental` | Rooms (5), Playstation (1); QR pass off. |
| `demo_event` | Grand Imperial Banquet, Karachi | `eventVenue` | Banquet halls (3); sessions; manual price. |
| `demo_vehicle` | Prime Drive Car Rental, Islamabad | `vehicleRental` | Hatchback, Sedan, Premium (3 each); own logo. |

**What this means for a backend:** each client is a **tenant**. Today a tenant is defined at compile time; the backend
should hold the same data per tenant (profile id, overrides, catalogue, settings) so that Phase 6 (catalogue as data) and
D5 (self-service) can move it out of the binary. The flavor/client id is the natural tenant key during migration.
Whether the future goes to "one generic app + login picks the tenant" instead of per-client builds is an open question
(section 13); a backend that supports both is the safe choice.

---

## 8. Business profiles

| Profile (`id`) | Terms (subject / resource / type / customer / fee) | Policy | Pricing | Features |
|---|---|---|---|---|
| `sportsVenue` (`sports_venue`) | Ground / Court / Sport / Player / Ground Fee | 30-min step, min 30 min, default 60, any hour | hourly | discount, QR pass |
| `spaceRental` (`space_rental`) | Space / Space / Property / Customer / Rental Fee | 60-min step, min 60, default 120, 24 h, "Full day" | hourly | discount, QR pass |
| `eventVenue` (`event_venue`) | Event / Hall / Venue / Client / Venue Fee | Sessions: Lunch 12–6 PM, Dinner 7 PM–12 AM, Full Day 10 AM–11 PM | manual | discount, QR pass |
| `vehicleRental` (`vehicle_rental`) | Rental / Vehicle / Vehicle / Customer / Rental Fee | 60-min step, min 60, default 120, any hour, can pass midnight | hourly | discount, QR pass |

A client can override `policy` (e.g. opening hours 4 PM–2 AM), `pricing`, and `features` (replaced as a whole).
A new kind of business = a new profile (data only).

---

## 9. Current storage and remote config

### 9.1 What lives where

| Data | Store | Backed up? | Shared between devices? |
|---|---|---|---|
| Bookings | Hive (`bookings`) | No | No |
| Booking id counter | Hive (`bookings_meta`) | No | No |
| Currency, hourly rates | SharedPreferences | No | No |
| Theme | SharedPreferences | No | No |
| Catalogue, profile, branding | Compiled into the app | via source | n/a |
| Licence / trial state | GitHub Gist + prefs cache | n/a | Read only |

### 9.2 Known data risks today

- Phone lost, reset or app uninstalled = all bookings lost (no backup, no export).
- Two phones at one business = two separate ledgers that can double-book each other.
- `TRF-####` ids are only unique per device.
- `AppHttpOverrides` accepts every SSL certificate (must be removed or restricted before release; a backend makes this urgent).

### 9.3 Remote trial / licence switch (current)

- One raw Gist URL (`AppClientConfig.accessConfigUrl`), fetched with a cache-busting query param and a 10 s timeout.

```json
{
  "clients": {
    "demo":      { "DataEntryStatus": 1, "IsAppEnable": true,  "AppDisableAfterDate": "" },
    "champions": { "DataEntryStatus": 1, "IsAppEnable": false, "AppDisableAfterDate": "2026-11-30" }
  }
}
```

| Rule | Behaviour |
|---|---|
| Trust | Only a `200` with GitHub's `x-github-request-id` header counts (captive portals and proxies are ignored). |
| `DataEntryStatus ≠ 1` | Entry ignored; app runs. |
| `IsAppEnable: false` | Blocked now, or from the day after `AppDisableAfterDate`; drawer shows days remaining until then. |
| Invalid JSON, no `clients`, or no entry for this client | **Fail closed**: "App Not Activated" until fixed. |
| Never fetched successfully (fresh install, offline) | **Fail open**: app runs. |
| Offline / errors later | Last good body (cached) still applies, so a block holds offline. |
| Clock tampering | "Now" = max(device time, GitHub `Date` header, latest time seen). |
| When checked | App start (during splash), resume, every minute while blocked, at most every 5 min while open, before opening the form and before saving. |
| Tolerant parsing | Accepts `"1"`, `"false"`, etc., since the Gist is hand-edited. |

A backend can take over this switch (per-tenant licence/subscription record), but must keep these behaviours, especially
fail-closed on a missing tenant, holding a block offline, and resistance to clock rewinds.

---

## 10. Roadmap

From `docs/EXPANSION_PLAN.md` (agreed 2026-10-21). Phases 1–4 are done.

| Phase | Status | Content | Backend impact |
|---|---|---|---|
| 1. Neutral core | done | `Sport`→`ResourceType`, `Court`→`Resource`, `Terms` | Legacy JSON keys `sport`/`courtId` remain. |
| 2. Booking policy | done | Steps, durations, opening hours, sessions, full day | Policy must be stored per tenant. |
| 3. Pricing | done | Hourly or manual per booking (schema v3) | |
| 4. Features | done | `discount`, `entryPass` flags | |
| Checkpoint | next | A second **real** client with another profile | |
| 5. Capacity (go/no-go) | planned | `Resource.capacity` (default 1), `Booking.places` (default 1); full when booked places reach capacity; price × places; schema v4 | Overlap rule becomes a **sum of places ≤ capacity**, not a simple exclusion. Pick a backend that can enforce that transactionally. |
| 6. Catalogue as data | planned | `CatalogRepository` seeded from config on first run; owner edits resources in Settings; icon keys; split business vs device settings | Resource types/resources/settings become syncable tenant data. |
| 7. Backend | after 6 | Database and sync; separate plan | This document feeds that plan. |
| D5 Self-service | future | A paying client configures their own business (profile, catalogue, terms) | Tenant config fully server-side; possibly a setup flow and sign-up. |

Other items mentioned for later: optional "extra charge" amount for hourly overruns; a random `uid` per booking for sync;
backup/export (postponed); release signing; native launch screen colour.

---

## 11. Backend requirements

Derived from everything above. "Must" = needed for the first online version; "Should" = expected soon after; "Later" = roadmap.

### 11.1 Functional

| # | Requirement | Priority |
|---|---|---|
| F1 | Store bookings per tenant (business) with the full field set of §4.2, keeping `v` and accepting older versions. | Must |
| F2 | **Offline-first**: the app must keep creating, editing, paying and cancelling with no internet, then sync. | Must |
| F3 | **Backup and restore**: a new or reinstalled phone signs in and gets the whole ledger back. | Must |
| F4 | **Server-side conflict guard**: two devices of the same business must not be able to confirm overlapping bookings on one resource (with Phase 5: places ≤ capacity). | Must if more than one device per business is allowed; Should otherwise |
| F5 | Authentication of the owner (phone number / email / Google) bound to one tenant. | Must |
| F6 | Licence / subscription per tenant replacing or mirroring the Gist switch (enable, disable, disable-after-date, not-activated). | Should |
| F7 | Tenant config as data: profile id, policy/pricing/features overrides, terms, catalogue, branding, currency, rates. | Later (Phase 6 / D5) |
| F8 | Globally unique booking key (`uid`) alongside the human `TRF-####` reference; reference numbering per tenant. | Must |
| F9 | Soft state only: no hard deletes; `updatedAt` on every record; last-writer or field-level merge policy defined. | Must |
| F10 | Multiple devices / staff users per tenant with roles (owner vs front desk). | Later (open question) |
| F11 | Developer console: list tenants, licence status, last sync, record counts (replaces hand-edited Gist). | Should |
| F12 | Export (CSV/PDF) of a tenant's ledger. | Later |
| F13 | Optional: hosted receipt link / QR verification endpoint; customer-facing booking page. | Later (open question) |

### 11.2 Non-functional

| # | Requirement |
|---|---|
| N1 | **Cost**: very low per tenant (small Pakistani businesses); free tier or cheap fixed cost at tens–hundreds of tenants. |
| N2 | **Flutter SDK quality**: mature Dart/Flutter client, ideally with built-in offline persistence or a proven sync layer. |
| N3 | **Multi-tenant isolation**: a tenant can only read and write its own data (row-level security or equivalent). |
| N4 | **Transactions / constraints** strong enough for F4 (exclusion or capacity check under concurrency). |
| N5 | **Latency/region**: usable from Pakistan on mobile data; the app must never block the UI on the network. |
| N6 | **Time handling**: store a tenant time zone; store booking start/end also as absolute instants for constraints; keep the local `date` + minutes form for the app. |
| N7 | **Schema evolution**: JSON-versioned records today; the backend must accept v1–v3 and future v4 without downtime. |
| N8 | **Small team**: one developer; prefer managed services over self-hosted servers. |
| N9 | **Vendor exit**: the repository interface already isolates the app; keep server logic portable (SQL or plain functions). |
| N10 | **Security**: proper TLS (remove `AppHttpOverrides`), no secrets in the app beyond public keys, auth tokens stored via the existing `UserStore`/prefs or secure storage. |

---

## 12. Backend design notes and options

Not a decision; inputs for one.

### 12.1 Suggested server-side shape

```
tenants(id = client id, name, profile_id, timezone, currency, country_code, overrides jsonb, created_at)
licences(tenant_id, data_entry_status, is_enabled, disable_after, updated_at)
users(id, auth provider id) ── memberships(user_id, tenant_id, role)
resource_types(tenant_id, id, label, short_label, icon_key, tone, default_rate, emoji, enabled, sort)
resources(tenant_id, id, type_id, name, description, capacity default 1, sort)
settings(tenant_id, currency_symbol, rates jsonb)
bookings(uid, tenant_id, ref 'TRF-1042', resource_type_id, resource_id, date, slots jsonb,
         starts_at timestamptz, ends_at timestamptz,          -- derived, for constraints and queries
         pricing, hourly_rate, total_fee, discount, advance_paid,
         balance_settled_at, cancelled_at, cancel_reason, advance_returned,
         customer_name, phone, email, notes,
         schema_v, created_at, updated_at, device_id)
ref_counters(tenant_id, last_number)
```

- The **no double booking** rule maps directly to a PostgreSQL exclusion constraint:
  `EXCLUDE USING gist (tenant_id WITH =, resource_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&) WHERE (cancelled_at IS NULL)`.
  Phase 5 capacity needs a transactional check (function or trigger) instead.
- Offline creation means a booking can be valid on the phone and rejected by the server later (another device took the slot).
  The sync design needs a **"rejected / conflict" state** the owner can resolve. With one device per business this cannot happen.
- `TRF-####` numbering per tenant: either assigned by the server on sync (then the receipt shows a temporary ref offline),
  or per-device prefixes / ranges. Decide before sync ships, because receipts are shared with customers.

### 12.2 Candidate families (to evaluate against §11)

| Option | Fits well | Watch out for |
|---|---|---|
| **Supabase** (Postgres + Auth + RLS + Edge Functions) | Relational data, exclusion constraint for F4, RLS for N3, SQL portability (N9), cheap start. | No built-in offline cache in the Flutter SDK: needs an outbox (as planned) or a sync layer (e.g. PowerSync). |
| **Postgres + PowerSync / ElectricSQL** (local SQLite synced with Postgres) | True local-first (F2), server constraints, conflict handling patterns. | Extra service and cost; would replace Hive with SQLite behind the same repository interface. |
| **Firebase** (Firestore + Auth + Cloud Functions) | Best-known Flutter SDK, built-in offline persistence, Remote Config could replace the Gist. | No native range-overlap constraint: F4 needs transactions on per-resource-per-day documents or Cloud Functions; NoSQL modelling of reports; cost grows with reads. |
| **Appwrite / PocketBase** (self-hosted or cloud) | Simple, cheap, Dart SDKs. | Offline sync and overlap constraints are manual; self-hosting conflicts with N8. |
| **Own API** (e.g. Dart Frog/Serverpod/Node + Postgres) | Full control; Dart backend could reuse `BookingRules`. Starter API layer already exists in the app. | Most work and operations for a one-person team. |

### 12.3 Migration path from today

1. Add `uid` (random) to `Booking` (schema v4 or folded into Phase 5's v4), keep `TRF-####` as `ref`.
2. Implement `SyncedBookingRepository` (Hive + outbox) behind `BookingRepository`; add sign-in.
3. First sign-in uploads the existing Hive ledger for that tenant (migration test on stored v1–v3 samples).
4. Move licence switch to the backend (keep Gist as fallback during rollout).
5. Phase 6 data (catalogue, settings) follows the same repository + outbox pattern.

---

## 13. Open questions for the owner

These change the backend choice; answer them first.

1. **Devices per business**: will a business use more than one phone/tablet at the same time? (Decides whether F4 is a must.)
2. **Users and roles**: owner only, or staff accounts with limited rights (e.g. staff can't cancel or see revenue)?
3. **Customer-facing features**: will customers ever book online, see availability, or receive receipts by link/SMS instead of WhatsApp image?
4. **App distribution**: keep one branded app per client, or move to one store app where login selects the business (with branding from the server)?
5. **Self-service sign-up (D5)**: when, and does it need online payment for subscriptions?
6. **Offline tolerance**: how long can a phone be offline (hours, days)? Is a server-side "conflict" after a long offline period acceptable?
7. **Budget**: target monthly cost per tenant and in total; acceptable to use a paid sync service?
8. **Data residency / compliance**: any requirement to keep data in Pakistan or a region? Customer phone numbers are personal data.
9. **Reporting**: does the owner (or DevCat) need cross-tenant analytics, monthly reports or accounting exports?
10. **Licensing**: should the backend become the source of truth for trials and subscriptions, replacing the Gist entirely?
