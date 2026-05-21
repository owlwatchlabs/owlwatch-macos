import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Owlwatch")
                .font(.largeTitle.bold())
            Text("M0 placeholder — companion lands at M14.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
