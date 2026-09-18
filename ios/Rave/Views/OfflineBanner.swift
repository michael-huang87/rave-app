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

/// Saved-here-not-there is the state the user most needs to see, so it outranks the offline and
/// refreshing banners: the edit is safe, it just has not reached the server.
struct PendingWritesBanner: View {
    var count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle")
            Text(count == 1 ? "1 change saved here, waiting for signal" : "\(count) changes saved here, waiting for signal")
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(RaveTheme.accent2)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RaveTheme.card)
        .accessibilityIdentifier("pending-writes-banner")
    }
}

struct CacheStatusBar: View {
    var fromCache: Bool
    var cachedAt: Date?
    var refreshing: Bool

    @State private var pending = 0

    var body: some View {
        Group {
            if pending > 0 {
                PendingWritesBanner(count: pending)
            } else if fromCache {
                OfflineBanner(cachedAt: cachedAt)
            } else if refreshing {
                RefreshingBanner()
            }
        }
        .task { pending = await Outbox.shared.count }
        .onReceive(NotificationCenter.default.publisher(for: Outbox.changed)) { note in
            pending = note.userInfo?["count"] as? Int ?? 0
        }
    }
}
