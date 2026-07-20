import SwiftUI

struct ConnectionView: View {
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            Text("Connect to Dot Wi‑Fi")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                Label("Open Settings → Wi‑Fi", systemImage: "1.circle.fill")
                Label("Join network Dot-XXXX", systemImage: "2.circle.fill")
                Label("Return here and tap Refresh", systemImage: "3.circle.fill")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Text("Device address: 192.168.4.1:8080")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ConnectionView(errorMessage: "The Internet connection appears to be offline.")
}
