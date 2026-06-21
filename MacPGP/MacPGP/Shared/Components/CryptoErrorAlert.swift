import SwiftUI

extension View {
    func cryptoErrorAlert(
        title: String = "Error",
        message: String?,
        isPresented: Binding<Bool>
    ) -> some View {
        alert(title, isPresented: isPresented) {
            Button("common.ok") {}
        } message: {
            Text(message ?? "An error occurred")
        }
    }
}
