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
   12 offline games. No ads.
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
2. Target → **General** → **Identity**: Version `1.0`, Build `1`. Every upload needs a higher
   build number: change **Build** (`CURRENT_PROJECT_VERSION`) before re-uploading, and commit
   that change (it holds nothing private).
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

## Step 9. The version page (1.0)

App Store Connect → your app → **iOS App 1.0** (left column).

1. **Screenshots** (drag them in, in this order):
   - **iPhone 6.9" display** (1320 × 2868): [`screenshots/iphone/`](./screenshots/iphone/)
     `01-home` … `08-snake`
   - **iPhone 6.3" display** (1206 × 2622), if App Store Connect asks for it:
     [`screenshots/iphone-medium/`](./screenshots/iphone-medium/)
   - **iPad 13" display** (2064 × 2752): [`screenshots/ipad/`](./screenshots/ipad/)
   App Store Connect scales these down for the other devices.
2. **Promotional Text** (170):
   ```
   Twelve beautifully made games that never need Wi-Fi: Sudoku, Solitaire, Chess, 2048, Word Guess and more. Free, with no ads, no accounts and no tracking.
   ```
3. **Description** (4000):
   ```
   Airplane Games is a collection of twelve polished games that work completely offline. Made for long flights, train rides and anywhere without Wi-Fi: no ads, no accounts, no tracking and nothing to download once it's installed.

   12 GAMES IN ONE APP
   • 2048: slide and merge tiles, with undo
   • Sudoku: four difficulty levels, notes, and hints that explain the next step
   • Solitaire: classic Klondike, draw 1 or draw 3, with auto-complete
   • Block Puzzle: fit blocks on the board and clear rows and columns
   • Tile Match: match pairs of free tiles across six original layouts
   • Minesweeper: every board solvable by logic, never a 50/50 guess, with flag mode and pinch to zoom
   • Chess: play the computer at five levels, or a friend on the same device
   • Word Guess: find the five-letter word in six tries, alone or with a friend
   • Nonograms: 44 original picture puzzles, all solvable by logic, with hints that explain why
   • Word Search: 15 themes in three sizes
   • Snake: three speeds, walls or wrap-around, swipe or D-pad
   • Hangman: a friendly hot-air balloon version, with categories and pass & play

   A NEW PUZZLE EVERY DAY
   Daily Sudoku, Word Guess, Solitaire, Minesweeper, Word Search and Tile Match: the same puzzle for everyone that day, made right on your device. Keep your streak going, even at 35,000 feet.

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
4. **Keywords** (100, commas without spaces; words already in the name, like "offline", "games"
   and "fun", are searched anyway, so they're left out):
   ```
   brain,no wifi,airplane mode,travel,flight,sudoku,solitaire,2048,chess,minesweeper,nonogram,puzzle
   ```
5. **Support URL**:
   ```
   https://github.com/guilhermechapiewski/airplane-games-app/issues
   ```
6. **Marketing URL**:
   ```
   https://guilhermechapiewski.github.io/airplane-games-app/
   ```
7. **Version**: `1.0`. **Copyright** (Apple adds the "©"):
   ```
   2026 Guilherme Chapiewski
   ```
8. **Build** → **+** → the build you tested in step 8.
9. **App Review Information**:
   - Sign-in required: **off** (the app has no accounts).
   - Contact: your first and last name, phone **with +1**, and email. Typed here only.
   - Notes:
     ```
     Airplane Games has no accounts, no in-app purchases and no network access; every game works offline, including in Airplane Mode. Tap any game's card on the home screen to play. The gear icon opens Settings (sound, haptics, theme, reset statistics) and About.
     ```
10. **Version Release**: **Manual** (you pick the launch moment after approval) or
    **Automatic**.
11. **Save**.

## Step 10. Submit

1. Top right: **Add for Review** → **Submit for Review**.
2. Review usually takes 1 to 3 days.
3. If Apple rejects it, the message is under **App Review**. Paste it to me and I'll fix the
   app or draft the reply.

## Step 11. After approval

1. **Release** it (if you chose Manual).
2. Replace "Coming soon" on the website (`docs/index.md`) with the App Store link,
   `https://apps.apple.com/app/id<the Apple ID on App Information>`. The Apple ID is public
   once the app is live.
3. **Accessibility Nutrition Labels** (optional): **App Accessibility** → **Get Started**.
   Declare only what you checked on a device (VoiceOver, Dark Interface, Reduced Motion...).
