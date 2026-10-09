# Buy It For Life (BIFL)

An iOS app for tracking the clothes you own and how much they really cost you over time.

## Target & platform

- iOS only (iPhone). No Android, no iPad focus, no web.
- Primary user: the developer himself, a guy with an iPhone.
- Visual style: a rather dark Apple "glass" (Liquid Glass) theme.

## Tech & workflow

- Written in **Swift** (native iOS).
- Solo project: the user is the only developer and the only tester.
- Claude may commit changes on its own. Claude must **not push** to GitHub — the user pushes.

## Data & privacy

- No backend server. All data is stored in **CloudKit** (the user's own iCloud).
- No accounts, no analytics, no tracking, no third-party data collection.

## Core concepts

An **item** is a piece of clothing with:
- Name / photo (taken with the camera or picked from the library)
- Purchase date
- Purchase price
- Weather it's suited for (e.g. warm, cold, rain — the kind of weather the item is worn in)
- Sold state: an item can be marked as sold, with the sale price recorded

A **wear log** records which items were worn on a given day.

## App structure — three tabs

1. **Wardrobe** — register and manage items (add, edit, photo, weather, mark as sold + sale price).
2. **Today / Calendar** — each day, input what you're wearing. A calendar lets you open and edit previous days.
3. **Statistics** —
   - Wardrobe level: total wardrobe cost, wardrobe cost per day.
   - Item level: cost per wear, item age.
   - Sold items should factor in their sale price (net cost = purchase price − sale price).

(Tab names above are descriptive; follow the designs for actual naming.)

## Onboarding

On first launch, show an onboarding flow that explains the app and lets the user register their first item.

## Designs

- Designs were made with Claude Design, and a Claude design system is in place.
- Design file: `design/bifl.html` (a self-unpacking bundled HTML — open in a browser to view).
- Follow the designs and the design system closely when building UI.
