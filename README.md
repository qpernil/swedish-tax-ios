# Swedish Tax 2026 for iOS

A native SwiftUI income planner and tax calculator based on Skatteverket's
2026 preliminary income-tax tables. The app is designed for iPhone, also runs
on iPad, and performs every calculation locally without a server or runtime
network dependency.

The calculation engine is a Swift translation of the existing C# and Rust
implementations. The interface carries over the Rust GUI's planning features
in a phone-first, vertically scrolling layout.

## Features

- Tax tables 29–42 and age-dependent table columns.
- Annual salary, monthly salary, one-time salary, monthly or annual
  occupational pension, and own-company dividends.
- Multiple income entries with exact 2026 start and end dates.
- Main-payer table withholding, secondary-payer 30% withholding, and custom
  withholding per entry.
- Jämkning as an adjustable percentage, selectable per payer, with optional
  full-year salary calibration.
- Vacation compensation based on annual entitlement and payment period, with
  suggested payout days and pension contribution estimates.
- Regular employer pension contributions, optional actual contribution values,
  and salary exchange with employer uplift and allowance validation.
- Annual final-tax and preliminary-withholding reconciliation, expected
  balance, marginal tax, PGI progress, SGI progress, and calculation trace.
- Complete local persistence of the selected table, age group, adjustment, and
  income plan.

If a salary-exchange amount becomes too high after another pension value is
changed, the plan is marked invalid and shows the newly permitted maximum.
Missing or malformed embedded tax data is reported separately from invalid
user input.

## Requirements

- Xcode 26 or later
- iOS 18 or later
- Swift 6

The iOS 18 deployment target is intentional: it provides native 128-bit
integer support used by the calculation engine, and this project has no
backward-compatibility requirement.

## Run in Xcode

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

The core is also a Swift package, so the full engine and parity suite can run
without launching the app:

```sh
swift test --disable-sandbox
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

The parity suite covers the official resource hash, every published table
boundary, monthly amount and percentage rows against the annual formula, SKV
433 worked examples and formula transitions. It also exercises mixed salary
and pension plans, payer precedence, jämkning calibration, exact payment
periods, vacation compensation, pension contributions, salary exchange,
dividends, PGI, SGI, and persistence round trips.

## Tax data

The official fixed-width monthly table is embedded unchanged at
`SwedishTax/Resources/allmanna-tabeller-manad-2026.txt`.

- Records: 7,966
- SHA-256: `8c5abe81d774ce083fec81ceed430282e39208c8b5a7a961a4760e4875e850ce`

The app validates the record count, record format, table range, and continuous
income coverage before using the resource. The checksum test protects the
official file against accidental edits.

## Persistence and privacy

The app saves a versioned JSON document in its Application Support directory.
It contains the complete income plan and tax settings and uses iOS complete
file protection. No income data is transmitted, and the app has no runtime
network integration.

Deleting the app also deletes this locally stored plan. There is currently no
iCloud synchronization or plan export.

## Project structure

```text
SwedishTax/
  App/                         SwiftUI application and phone interface
  Core/                        Tax engine, income planning, and persistence
  Resources/                   Official table and application icon assets
SwedishTaxTests/               Engine, resource, and parity tests
SwedishTax.xcodeproj/          Native iOS project
Package.swift                  Standalone core test package
```

## Official sources

- [SKV 433 technical specification](https://www.skatteverket.se/download/18.1522bf3f19aea8075ba55c/1766385913260/teknisk-beskrivning-skv-433-2026-utgava-36.pdf)
- [Official monthly tables](https://www.skatteverket.se/download/18.1522bf3f19aea8075ba5af/1765287119989/allmanna-tabeller-manad.txt)
- [Worked examples](https://www.skatteverket.se/download/18.1522bf3f19aea8075ba55f/1765284831853/bilaga-3-exempel-till-skv-433-2026.pdf)
- [2026 pensionable income (PGI)](https://www.skatteverket.se/privat/skatter/arbeteochinkomst/pensionsgrundandeinkomstpgi.4.4f3d00a710cc9ae1c9c80008300.html)
- [Sickness-benefit qualifying income (SGI)](https://www.forsakringskassan.se/privatperson/sjukpenninggrundande-inkomst-sgi)

## Scope

The result is a preliminary planning estimate based on the published tables
and the assumptions implemented by the source engines. It is not an
individualized final tax assessment or financial advice.
