# Swedish Tax 2026 for iOS

A native SwiftUI income planner backed by the shared Rust tax core and based on
Skatteverket's 2026 preliminary income-tax tables. The app is designed for
iPhone, also runs on iPad, and performs every calculation locally without a
server or runtime network dependency.

Swift owns the interface, persistence, and Apple-platform integration. The
complete displayed plan calculation crosses a versioned, typed C ABI into
Rust. Rust is the single source of truth for tax tables, annual tax, income
bases, withholding, pension calculations, and complete plan results.

## Features

- Tax tables 29–42 and age-dependent table columns.
- Annual salary, monthly salary, one-time salary, monthly or annual
  occupational pension, and own-company dividends.
- Multiple income entries with exact 2026 start and end dates.
- Multiple named calculations with switching, duplication, renaming, and
  deletion.
- Main-payer table withholding, secondary-payer 30% withholding, and voluntary
  additional withholding in SEK per payment.
- Jämkning as an adjustable percentage, selectable per payer, with optional
  full-year salary calibration.
- Vacation compensation based on annual entitlement and payment period, with
  suggested payout days and pension contribution estimates.
- Regular employer pension contributions, optional actual contribution values,
  and salary exchange with employer uplift and allowance validation.
- Annual final-tax and preliminary-withholding reconciliation, expected
  balance, marginal tax, PGI progress, SGI progress, and calculation trace.
- Complete local persistence of every named calculation and the current
  selection.

If a salary-exchange amount becomes too high after another pension value is
changed, the plan is marked invalid and shows the newly permitted maximum.
Missing or malformed embedded tax data is reported separately from invalid
user input.

## Requirements

- Xcode 26 or later
- iOS 18 or later
- Swift 6
- Rust with the `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets

The iOS 18 deployment target is intentional: it provides native 128-bit
integer support used by the calculation engine, and this project has no
backward-compatibility requirement.

## Run in Xcode

The generated Rust XCFramework is intentionally not committed to the iOS
repository. Build its device and Apple Silicon simulator slices in the
`swedish-tax` repository:

```sh
cargo xtask ios
```

This creates `target/ios/SwedishTaxCore.xcframework`. Give Xcode the containing
directory through its `RUST_CORE_ARTIFACTS_DIR` build setting. For example:

```sh
xcodebuild \
  -project SwedishTax.xcodeproj \
  -scheme SwedishTax \
  RUST_CORE_ARTIFACTS_DIR="/absolute/path/to/swedish-tax/target/ios" \
  build
```

The Xcode project persists `RUST_CORE_ARTIFACTS_DIR` for Debug and Release as
`$(SRCROOT)/../swedish-tax/target/ios`, so adjacent clones work with an ordinary
Xcode **Run** or **Build**. If the repositories live elsewhere, change that
user-defined setting once in the app target's **Build Settings**; subsequent
GUI builds reuse it.

The Rust artifact is a required build dependency. Xcode automatically selects
the device or simulator slice from the XCFramework.

1. Open `SwedishTax.xcodeproj`.
2. Select the `SwedishTax` target and open **Signing & Capabilities**.
3. Choose your Apple development team. If necessary, change the bundle
   identifier to a value unique to your account.
4. Connect and unlock the iPhone, select it as the run destination, and press
   **Run**.
5. The first time, enable **Developer Mode** on the phone if iOS asks for it.
   If iOS reports that apps from the developer are not allowed, trust the
   developer profile under **Settings → General → VPN & Device Management**.

Each phone that runs a development build must be registered and provisioned by
the selected development team. Distribution through TestFlight or the App
Store uses an Apple Developer Program membership and does not require each
recipient to enable Developer Mode.

## Tests

Run the Rust core's comprehensive unit and integration suite in the Rust
repository:

```sh
cargo test --workspace
```

To verify that the native device target compiles without signing it:

```sh
xcodebuild \
  -project SwedishTax.xcodeproj \
  -scheme SwedishTax \
  -sdk iphoneos \
  -configuration Debug \
  -derivedDataPath /tmp/swedish-tax-ios-derived \
  build CODE_SIGNING_ALLOWED=NO
```

The Xcode suite calls the Rust XCFramework through Swift and checks fixed table
boundaries, an SKV 433 worked example, complete plan results, payer precedence,
jämkning, vacation compensation, salary exchange, dividends, PGI, SGI, and
persistence round trips. This verifies the C ABI, generated header, native
linkage, ownership of returned buffers, and Swift mapping without maintaining
a second tax engine.

## Tax data

The official fixed-width monthly table is owned and embedded by the Rust core.
Its Rust tests verify:

- Records: 7,966
- SHA-256: `8c5abe81d774ce083fec81ceed430282e39208c8b5a7a961a4760e4875e850ce`

The Rust core validates the record count, record format, table range, and
continuous income coverage before using the resource. Its checksum test
protects the official file against accidental edits.

## Persistence and privacy

The app saves a versioned JSON workspace in its Application Support directory.
It contains every named calculation, each complete income plan and its tax
settings, and the current selection. The workspace uses iOS complete file
protection. No income data is transmitted, and the app has no runtime network
integration.

Deleting the app also deletes these locally stored calculations. There is
currently no iCloud synchronization or calculation export.

## Project structure

```text
SwedishTax/
  App/                         SwiftUI application and phone interface
  Core/                        Rust FFI mapping, plan model, and persistence
  Resources/                   Application icon assets
SwedishTaxTests/               Native bridge, UI-model, and persistence tests
SwedishTax.xcodeproj/          Native iOS project
```

## Official sources

- [SKV 433 technical specification](https://www.skatteverket.se/download/18.1522bf3f19aea8075ba55c/1766385913260/teknisk-beskrivning-skv-433-2026-utgava-36.pdf)
- [Official monthly tables](https://www.skatteverket.se/download/18.1522bf3f19aea8075ba5af/1765287119989/allmanna-tabeller-manad.txt)
- [Worked examples](https://www.skatteverket.se/download/18.1522bf3f19aea8075ba55f/1765284831853/bilaga-3-exempel-till-skv-433-2026.pdf)
- [2026 pensionable income (PGI)](https://www.skatteverket.se/privat/skatter/arbeteochinkomst/pensionsgrundandeinkomstpgi.4.4f3d00a710cc9ae1c9c80008300.html)
- [Sickness-benefit qualifying income (SGI)](https://www.forsakringskassan.se/privatperson/sjukpenninggrundande-inkomst-sgi)

## Scope

The result is a preliminary planning estimate based on the published tables
and the assumptions implemented by the Rust core. It is not an
individualized final tax assessment or financial advice.
