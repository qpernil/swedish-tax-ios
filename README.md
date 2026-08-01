# Swedish Tax 2026 for iOS

A fully native SwiftUI calculator and income planner for Skatteverket's 2026
preliminary income tax. The phone-first interface supports multiple annual,
monthly, and one-time salary entries; occupational pension; own-AB dividends;
exact payment periods; payer-specific withholding; jämkning; vacation
compensation; employer pension estimates; and salary exchange. Results include
final-tax and withholding reconciliation, marginal tax, PGI and SGI ceilings,
a calculation trace, and the complete annual breakdown.

The calculation engine is a Swift translation of the C# and Rust engines. It
runs entirely on-device and has no runtime network dependency.

## Requirements

- Xcode 26 or later
- iOS 18 or later

Open `SwedishTax.xcodeproj`, select the `SwedishTax` scheme, and run on an iOS
simulator or device.

From the command line:

```sh
xcodebuild test \
  -project SwedishTax.xcodeproj \
  -scheme SwedishTax \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Tax data and parity

The official fixed-width monthly table is embedded unchanged at
`SwedishTax/Resources/allmanna-tabeller-manad-2026.txt`.

- Records: 7,966
- SHA-256: `8c5abe81d774ce083fec81ceed430282e39208c8b5a7a961a4760e4875e850ce`

The test suite checks the resource hash, every published table boundary, every
monthly amount and percentage row against the annual formula, the SKV 433
worked examples, formula transitions, invalid inputs, mixed salary and pension
profiles, one-time withholding, and Rust GUI parity scenarios for jämkning,
vacation compensation, pension contributions, salary exchange, and dividends.

## Official sources

- [SKV 433 technical specification](https://www.skatteverket.se/download/18.1522bf3f19aea8075ba55c/1766385913260/teknisk-beskrivning-skv-433-2026-utgava-36.pdf)
- [Official monthly tables](https://www.skatteverket.se/download/18.1522bf3f19aea8075ba5af/1765287119989/allmanna-tabeller-manad.txt)
- [Worked examples](https://www.skatteverket.se/download/18.1522bf3f19aea8075ba55f/1765284831853/bilaga-3-exempel-till-skv-433-2026.pdf)
- [2026 pensionable income (PGI)](https://www.skatteverket.se/privat/skatter/arbeteochinkomst/pensionsgrundandeinkomstpgi.4.4f3d00a710cc9ae1c9c80008300.html)
- [Sickness-benefit qualifying income (SGI)](https://www.forsakringskassan.se/privatperson/sjukpenninggrundande-inkomst-sgi)

The calculations use the assumptions in the published tables and are not an
individualized final tax assessment.
