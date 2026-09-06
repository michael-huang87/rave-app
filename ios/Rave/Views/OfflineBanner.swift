import SwiftUI

struct OfflineBanner: View {
    var cachedAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            VStack(alignment: .leading, spacing: 1) {
                Text("Offline — last loaded data")
                if let cachedAt {
                    Text(cachedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(RaveTheme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RaveTheme.card)
        .accessibilityIdentifier("offline-banner")
    }
}
