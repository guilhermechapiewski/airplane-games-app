# Publishing Airplane Games to the App Store

## Step 1. Publish the website and privacy policy (done 2026-11-23)

Apple needs a privacy policy URL. The pages are in [`docs/`](../docs/) and are served by GitHub
Pages (branch **main**, folder **/docs**), like Samsung Remote's. Every push to `main` updates them.
Both open:
   - https://guilhermechapiewski.github.io/airplane-games-app/
   - https://guilhermechapiewski.github.io/airplane-games-app/privacy/

## Step 2. Signing (once per Mac)

Set the team in the git-ignored local file, **not** in Xcode's Signing & Capabilities pane:
Xcode writes that choice into `project.pbxproj`, which is public.

1. In Terminal, from the repository folder:
   ```
   cp Config/Local.example.xcconfig Config/Local.xcconfig
   ```
2. Open `Config/Local.xcconfig` and replace `YOUR_TEAM_ID` with your team ID
   (developer.apple.com → **Account** → **Membership details** → Team ID).
3. Open the project in Xcode → target **AirplaneModeGames** → **Signing & Capabilities**: it
   should show your team, with **Automatically manage signing** on. If `git status` ever shows
   `project.pbxproj` changed with a `DEVELOPMENT_TEAM` line, don't commit it.

## Step 3. Register the bundle ID and create the app record

1. https://developer.apple.com/account/resources/identifiers/list → **+** → **App IDs** →
   **App** → Description `Airplane Games`, **Explicit** Bundle ID:
   ```
   com.gchapiewski.airplanemodegames
   ```
   No capabilities are needed → **Continue** → **Register**. (Xcode's automatic signing may
   already have done this; if it's in the list, skip ahead.)
2. https://appstoreconnect.apple.com → **Apps** → **+** → **New App**:

   | Field | Value |
   |---|---|
   | Platforms | **iOS** |
   | Name | the box below |
   | Primary Language | **English (U.S.)** |
   | Bundle ID | **com.gchapiewski.airplanemodegames** (pick it from the list) |
   | SKU | `airplane-games-ios` (private, any unique text) |
   | User Access | **Full Access** |

   Name (30 characters at most):
   ```
   Airplane Games: Offline Fun
   ```
   Done (2026-11-23): "Airplane Mode Games" was taken; this name was accepted. The App Store
   name is the only change: the bundle ID stays the same and the home screen keeps showing
   **Airplane Games**.
3. **Create**.

## Step 4. App Information and the age rating

App Store Connect → your app → **General** → **App Information**.

1. **Subtitle** (30):
   ```
   Puzzles, cards & more. No ads.
   ```
2. **Category**: Primary **Games**, with subcategories **Puzzle** and **Board**. Secondary:
   **Entertainment** (optional).
3. **Content Rights**: "No, it does not contain, show, or access third-party content." (Every
   game, puzzle and word list is original or public domain; see
   `Packages/GameLogic/Sources/GameLogic/Resources/WORDLISTS.md`.)
4. **Age Ratings** → **Set Up Age Ratings**. Answer every question **No** or **None**:
   - In-App Controls, Capabilities (web access, user-generated content, messaging,
     advertising...): all **No**.
   - Mature Themes, Medical, Sexuality or Nudity, Violence, **Chance-Based Activities**: all
     **None** / **No**. Solitaire has no betting or prizes, so it isn't gambling.
   - The calculated rating should be **4+**. Don't choose **Made for Kids**: that's the Kids
     Category, which has extra rules and can't be undone.
   - **Save**.
5. **Save** the page.

## Step 5. Pricing and Availability

Your app → **Monetization** → **Pricing and Availability**.

1. **Price Schedule** → **Add Pricing** → base country **United States** → **$0.00 (Free)** →
   **Next** → **Confirm**.
2. **App Availability** → **all countries and regions** (the games need no translation to be
   played; the menus are in English) → **Confirm**.
3. **Trader status (EU Digital Services Act)**: Apple asks everyone: **Business** →
   **Agreements** → **Compliance** → **Digital Services Act**. A free app published by an
   individual, not as a business, is usually **not a trader**, but the choice is your own
   assessment. A trader's address, phone and email are shown publicly on EU App Store pages.

## Step 6. App Privacy

Your app → **General** → **App Privacy**.

1. **Privacy Policy URL**:
   ```
   https://guilhermechapiewski.github.io/airplane-games-app/privacy/
   ```
   **Save**.
2. **Data Collection** → **Get Started** → "**No, we do not collect data from this app**" →
   **Save** → **Publish**. The label then reads **Data Not Collected**. That's true: the app has
   no network code at all.

## Step 7. Build and upload

1. `git pull`. In Xcode: scheme **AirplaneModeGames** → destination **Any iOS Device (arm64)**.
2. Target → **General** → **Identity**: Version `1.1`, Build `3` (builds 1 and 2 were uploaded
   as 1.0). Every upload needs a higher build number: change **Build**
   (`CURRENT_PROJECT_VERSION`) before re-uploading, and commit that change (it holds nothing
   private). The Version must match the version page in App Store Connect.
3. **Product → Archive** (Release configuration: no debug launch arguments).
4. The **Organizer** opens → the archive → **Distribute App** → **App Store Connect** →
   **Distribute**.
5. After 5–30 minutes, **TestFlight** shows the build and you get an email.

## Step 8. Test it with TestFlight

1. **TestFlight** → **+** next to **Internal Testing** → name the group → **Create** →
   **Invite Testers** → add yourself.
2. Install **TestFlight** from the App Store on your iPhone, accept the invite, install.
3. Turn on **Airplane Mode** first, then check:
   - [ ] Every game opens from its card and plays.
   - [ ] Leave a game mid-way, force-quit the app, reopen: it's under **Continue Playing**.
   - [ ] The game's card asks before erasing a game in progress.
   - [ ] Sound and haptics follow **Settings**; the silent switch mutes sounds.
   - [ ] **Settings → About**: the version is right; the links open (with Airplane Mode off).
   - [ ] On an iPad, if you have one: portrait and landscape.
4. Anything wrong? Fix it before submitting.

## Step 9. The version page (1.1)

App Store Connect → your app → **iOS App 1.1** (left column). If it isn't there, click **+**
next to **iOS App** and enter `1.1`. A new version page copies the previous version's text and
screenshots, so check them rather than retyping them.

1. **Screenshots** (drag them in, in this order):
   - **iPhone 6.9" display** (1320 × 2868): [`screenshots/iphone/`](./screenshots/iphone/)
     `01-home` … `10-word-wheel`
   - **iPhone 6.3" display** (1206 × 2622), if App Store Connect asks for it:
     [`screenshots/iphone-medium/`](./screenshots/iphone-medium/)
   - **iPad 13" display** (2064 × 2752): [`screenshots/ipad/`](./screenshots/ipad/)
   App Store Connect scales these down for the other devices.
2. **What's New in This Version** (4000; Apple shows this box only for updates, not the first
   version):
   ```
   Fixes and polish:
   • Result cards now keep every stat on screen, even when a game shows four of them on a smaller iPhone.
   • A result card taller than the screen, like Word Guess with large text, now scrolls, so its buttons are always reachable.
   ```
3. **Promotional Text** (170):
   ```
   Beautifully made games that never need Wi-Fi: Sudoku, Solitaire, Chess, 2048, Word Guess and more. Free, with no ads, no accounts and no tracking.
   ```
4. **Description** (4000):
   ```
   Airplane Games is a collection of polished games that work completely offline. Made for long flights, train rides and anywhere without Wi-Fi: no ads, no accounts, no tracking and nothing to download once it's installed.

   THE GAMES
   • 2048: slide and merge tiles, with undo
   • Sudoku: four difficulty levels, notes, and hints that explain the next step
   • Solitaire: classic Klondike, draw 1 or draw 3, with auto-complete
   • FreeCell: every card face up, numbered deals that can all be won, and hints that find the way
   • Block Puzzle: fit blocks on the board and clear rows and columns
   • Tile Match: match pairs of free tiles across six original layouts
   • Water Sort: pour until every tube is one color, with endless levels
   • Minesweeper: every board solvable by logic, never a 50/50 guess, with flag mode and pinch to zoom
   • Chess: play the computer at five levels, or a friend on the same device
   • Dots and Boxes: close the most boxes, against the computer or a friend
   • Word Guess: find the five-letter word in six tries, alone or with a friend
   • Word Wheel: make words from seven letters around a center letter
   • Nonograms: 44 original picture puzzles, all solvable by logic, with hints that explain why
   • Word Search: 15 themes in three sizes
   • Snake: four speeds from slow to fast, three board sizes, walls or wrap-around
   • Hangman: a friendly hot-air balloon version, with categories and pass & play

   MADE FOR TRAVEL
   • Works in airplane mode: every game, every time
   • Pick up where you left off: every game saves automatically
   • Play against the computer, or pass the phone to a friend
   • Statistics and best scores for every game
   • Sound effects and haptics you can turn off, plus light and dark mode
   • Designed for iPhone and iPad, with VoiceOver support

   PRIVATE BY DESIGN
   No ads, no in-app purchases, no accounts, no analytics and no network access at all. Your games and statistics never leave your device.

   FREE AND OPEN SOURCE
   Airplane Games is completely free, with nothing to unlock. Its source code is published on GitHub under the MIT license.
   ```
5. **Keywords** (100, commas without spaces; words already in the name, like "offline", "games"
   and "fun", are searched anyway, so they're left out):
   ```
   brain,no wifi,airplane mode,travel,flight,sudoku,solitaire,2048,chess,minesweeper,nonogram,puzzle
   ```
6. **Support URL**:
   ```
   https://github.com/guilhermechapiewski/airplane-games-app/issues
   ```
7. **Marketing URL**:
   ```
   https://guilhermechapiewski.github.io/airplane-games-app/
   ```
8. **Version**: `1.1`. **Copyright** (Apple adds the "©"):
   ```
   2026 Guilherme Chapiewski
   ```
9. **Build** → **+** → the build you tested in step 8.
10. **App Review Information**:
   - Sign-in required: **off** (the app has no accounts).
   - Contact: your first and last name, phone **with +1**, and email. Typed here only.
   - **Attachment**: the screen recording from [Step 9a](#step-9a-the-screen-recording-for-app-review).
   - **Notes** (4000; fill in the two `[...]` in item 1 first):
     ```
     1. SCREEN RECORDING
     Attached. Recorded on [iPhone model] running iOS [version], starting from launching the app with Airplane Mode on, then playing several games. The app has no account registration or login, no user-generated content and no paid content, so there are no such flows to show.

     2. PURPOSE AND AUDIENCE
     Airplane Games is a free collection of classic puzzle, card, board, word and arcade games (Sudoku, Solitaire, FreeCell, Chess, Minesweeper, Word Guess, 2048 and more) that work completely offline. It is for anyone who wants something good to play without an internet connection: on flights, trains and subways, abroad without data, or anywhere with poor reception. Many game apps need a connection for ads, accounts or downloads and stop working offline; this one needs nothing after it is installed, and has no ads, no in-app purchases and no tracking.

     3. HOW TO USE THE APP
     No login, setup or sample files are needed. Open the app and tap any game's card on the home screen to start playing. Inside every game, the menu (top right) has How to Play with the rules and tips, and the toolbar has Undo, Hint and New Game where the game supports them. Chess and Dots and Boxes can be played against the computer or with a friend on the same device; Word Guess and Hangman also have a pass-and-play mode where a friend picks the secret word. Games save automatically: leave a game and it appears under Continue Playing on the home screen. The gear icon opens Settings (sound, haptics, appearance, reset statistics) and About (version, privacy policy, source code).

     4. EXTERNAL SERVICES
     None. The app makes no network requests and contains no third-party SDKs: no analytics, advertising, authentication, payment, cloud or AI services. All game logic, puzzles and word lists are bundled in the app.

     5. REGIONAL DIFFERENCES
     None. The app works the same in every region. Its interface and word games are in English.

     6. REGULATED INDUSTRY OR THIRD-PARTY MATERIAL
     Not applicable. The app is not in a regulated industry and contains no protected third-party material. The games are traditional games implemented from scratch; the artwork, puzzles and themed word lists are original, and the dictionary word lists are public domain. The source code is public under the MIT license: https://github.com/guilhermechapiewski/airplane-games-app
     ```
11. **Version Release**: **Manual** (you pick the launch moment after approval) or
    **Automatic**.
12. **Save**.

## Step 9a. The screen recording for App Review

App Review asked for this on 2026-11-25. Record it on a physical iPhone with the latest iOS,
running the TestFlight build you're submitting.

1. **Settings → Control Center**: make sure **Screen Recording** is in Control Center.
2. Close Airplane Games if it's open (swipe it away in the app switcher), so the recording
   shows a real launch.
3. Open Control Center, turn on **Airplane Mode** (so the recording shows it working offline),
   tap **Screen Recording**, and wait for the countdown.
4. On the home screen, tap **Airplane Games** to launch it. Then, in about 2–3 minutes:
   - Scroll the home screen to show the games.
   - Play a few moves of Sudoku: tap a cell, a number, then **Hint**.
   - Back. Open Solitaire: move a card or two; tap **Undo**.
   - Back. Open Chess: make a move against the computer and wait for its reply.
   - Back. Open Word Guess: type a guess and submit it.
   - Back: the games you left appear under **Continue Playing**; tap one to resume it.
   - In a game, open the menu → **How to Play**.
   - The gear → **Settings** → **About**.
5. Stop the recording (the red indicator at the top → **Stop**). It's saved to Photos.
6. Trim it in Photos if needed, AirDrop it to your Mac, and add it under **App Review
   Information → Attachment**. (If the file is too large, export it at a lower resolution
   from Photos or QuickTime.)

## Step 10. Submit

1. Top right: **Add for Review** → **Submit for Review**.
2. Review usually takes 1 to 3 days.
3. If Apple rejects it, the message is under **App Review**. Paste it to me and I'll fix the
   app or draft the reply.

## Step 11. After approval

1. **Release** it (if you chose Manual).
2. *Done 2026-11-23:* the website shows Apple's "Download on the App Store" badge, linking to
   https://apps.apple.com/app/id6838496554 (the Apple ID on App Information). The link works
   once Apple releases the app.
3. **Accessibility Nutrition Labels** (optional): **App Accessibility** → **Get Started**.
   Declare only what you checked on a device (VoiceOver, Dark Interface, Reduced Motion...).
