import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section(String(localized: "sidebar.section.keys", defaultValue: "Keys", comment: "Sidebar section header for keys")) {
                NavigationLink(value: SidebarItem.keyring) {
                    Label(SidebarItem.keyring.displayName, systemImage: SidebarItem.keyring.iconName)
                }
                NavigationLink(value: SidebarItem.webOfTrust) {
                    Label(SidebarItem.webOfTrust.displayName, systemImage: SidebarItem.webOfTrust.iconName)
                }
            }

            Section(String(localized: "sidebar.section.operations", defaultValue: "Operations", comment: "Sidebar section header for operations")) {
                ForEach([SidebarItem.encrypt, .decrypt, .sign, .verify]) { item in
                    NavigationLink(value: item) {
                        Label(item.displayName, systemImage: item.iconName)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MacPGP")
        .frame(minWidth: 180)
    }
}

#Preview {
    NavigationSplitView {
        SidebarView(selection: .constant(.keyring))
    } detail: {
        Text("Detail")
    }
}
