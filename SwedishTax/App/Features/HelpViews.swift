import SwiftUI

enum HelpTopic: String, Identifiable {
    case table, age, adjustment, marginalRate, incomeBases
    var id: Self { self }
}

struct HelpSheet: View {
    let topic: HelpTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch topic {
                    case .table:
                        Text("Find your tax table").font(.title2.bold())
                        Text("Your A-tax certificate from Skatteverket states which table your payer should use. It is normally based on where you were registered on 1 November of the preceding year.")
                    case .age:
                        Text("Age and table columns").font(.title2.bold())
                        Text("Under 66 uses column 1 for salary and column 6 for pension. Age 66 or older uses column 3 for salary and column 2 for pension. Age is determined at the start of the income year.")
                    case .adjustment:
                        Text("Jämkning").font(.title2.bold())
                        Text("Enter the percentage from a Skatteverket decision and mark the payers that received it. A full-year recurring salary basis can calibrate the annual projection while the entered dates still control actual cash income.")
                    case .marginalRate:
                        Text("Marginal tax").font(.title2.bold())
                        Text("The app adds 12,000 SEK of annual work income and compares the two annual formula results. The additional tax is shown as a percentage.")
                    case .incomeBases:
                        Text("PGI and SGI estimates").font(.title2.bold())
                        Text("PGI uses aggregate pensionable work income after the general pension fee. SGI uses the annualized rate of recurring salary. Försäkringskassan determines actual SGI.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    Label("Income year 2026", systemImage: "calendar")
                    Label("Tables 29–42", systemImage: "tablecells")
                    Label("SKV 433, edition 36", systemImage: "doc.text")
                    Label("Works entirely offline", systemImage: "lock.shield")
                }
                Section("Included planning features") {
                    Text("Multiple salary, pension, one-time payment, and own-AB dividend entries")
                    Text("Payer withholding, jämkning, vacation compensation, occupational pension, and salary exchange")
                }
                Section("Important") {
                    Text("This is a preliminary calculation using published-table assumptions. It is not an individualized final tax, pension, SGI, or salary-exchange assessment.")
                }
                Section("Official sources") {
                    Link("SKV 433 technical specification", destination: URL(string: "https://www.skatteverket.se/download/18.1522bf3f19aea8075ba55c/1766385913260/teknisk-beskrivning-skv-433-2026-utgava-36.pdf")!)
                    Link("Skatteverket monthly tables", destination: URL(string: "https://www.skatteverket.se/download/18.1522bf3f19aea8075ba5af/1765287119989/allmanna-tabeller-manad.txt")!)
                    Link("2026 pensionable income (PGI)", destination: URL(string: "https://www.skatteverket.se/privat/skatter/arbeteochinkomst/pensionsgrundandeinkomstpgi.4.4f3d00a710cc9ae1c9c80008300.html")!)
                    Link("Sickness-benefit qualifying income (SGI)", destination: URL(string: "https://www.forsakringskassan.se/privatperson/sjukpenninggrundande-inkomst-sgi")!)
                }
                Section("Rust core and native bridge") {
                    Text("The shared tax-calculation engine is written in Rust.")
                    Text("The SwiftUI interface calls it through a versioned, typed C FFI bridge.")
                    Text("The Swift interface and Rust engine run together as native ARM machine code inside the app, without an interpreter, virtual machine, separate process, or server dependency.")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
