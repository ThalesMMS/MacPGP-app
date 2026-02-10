import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Keys") {
                NavigationLink(value: SidebarItem.keyring) {
                    Label(SidebarItem.keyring.rawValue, systemImage: SidebarItem.keyring.iconName)
                }
                NavigationLink(value: SidebarItem.webOfTrust) {
                    Label(SidebarItem.webOfTrust.rawValue, systemImage: SidebarItem.webOfTrust.iconName)
                }
            }

            Section("Operations") {
                ForEach([SidebarItem.encrypt, .decrypt, .sign, .verify]) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.iconName)
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
