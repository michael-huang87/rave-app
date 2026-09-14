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

/// Shown while a background GET runs over already-painted last-read data. Not a loading gate.
struct RefreshingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Updating…")
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RaveTheme.card)
        .accessibilityIdentifier("refreshing-banner")
        .accessibilityLabel("Updating")
    }
}

struct CacheStatusBar: View {
    var fromCache: Bool
    var cachedAt: Date?
    var refreshing: Bool

    var body: some View {
        if fromCache {
            OfflineBanner(cachedAt: cachedAt)
        } else if refreshing {
            RefreshingBanner()
        }
    }
}
