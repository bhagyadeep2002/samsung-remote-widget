import SwiftUI
import WidgetKit

private struct RemoteEntry: TimelineEntry {
    let date: Date
    let isPaired: Bool
    let status: String
}

private struct RemoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> RemoteEntry {
        RemoteEntry(date: .now, isPaired: true, status: "Ready")
    }

    func getSnapshot(in context: Context, completion: @escaping (RemoteEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RemoteEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> RemoteEntry {
        let host = SharedPreferences.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasToken = (try? PairingCredentialStore.token(for: host)) != nil
        let hasCertificatePin = (try? PairingCredentialStore.certificatePin(for: host)) != nil
        return RemoteEntry(
            date: .now,
            isPaired: !host.isEmpty && hasToken && hasCertificatePin,
            status: SharedPreferences.status
        )
    }
}

private struct RemoteWidgetContent: View {
    let entry: RemoteEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.isPaired {
            if family == .systemSmall {
                smallRemote
            } else {
                mediumRemote
            }
        } else {
            setupPrompt
        }
    }

    private var smallRemote: some View {
        VStack(spacing: 6) {
            header
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                remoteButton(.up, symbol: "chevron.up")
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                remoteButton(.left, symbol: "chevron.left")
                remoteButton(.select, symbol: "circle")
                remoteButton(.right, symbol: "chevron.right")
            }
            HStack(spacing: 6) {
                remoteButton(.back, symbol: "arrow.uturn.backward")
                remoteButton(.down, symbol: "chevron.down")
                remoteButton(.home, symbol: "house")
            }
        }
        .padding(.horizontal, 5)
    }

    private var mediumRemote: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                header
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    remoteButton(.up, symbol: "chevron.up")
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    remoteButton(.left, symbol: "chevron.left")
                    remoteButton(.select, symbol: "circle")
                    remoteButton(.right, symbol: "chevron.right")
                }
                HStack(spacing: 6) {
                    remoteButton(.back, symbol: "arrow.uturn.backward")
                    remoteButton(.down, symbol: "chevron.down")
                    remoteButton(.home, symbol: "house")
                }
            }

            VStack(spacing: 8) {
                remoteButton(.powerOff, symbol: "power")
                remoteButton(.volumeUp, symbol: "speaker.plus")
                remoteButton(.mute, symbol: "speaker.slash")
                remoteButton(.volumeDown, symbol: "speaker.minus")
            }
            .frame(width: 52)

            VStack(spacing: 8) {
                remoteButton(.play, symbol: "play.fill")
                remoteButton(.pause, symbol: "pause.fill")
            }
            .frame(width: 48)
            .padding(.top, 22)
        }
        .padding(.horizontal, 6)
    }

    private var header: some View {
        HStack {
            Text("Samsung TV")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 4)
            if family == .systemSmall {
                remoteButton(.powerOff, symbol: "power")
                    .frame(width: 34)
            }
        }
        .frame(height: 28)
    }

    private var setupPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Samsung TV", systemImage: "tv")
                .font(.headline)
            Text(entry.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Button(intent: OpenRemoteSetupIntent()) {
                Text("Open setup")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func remoteButton(_ key: SamsungRemoteKey, symbol: String) -> some View {
        Button(intent: SendRemoteKeyIntent(key: key)) {
            Image(systemName: symbol)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(key.spokenName)
    }
}

struct SamsungTVRemoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SamsungTVRemoteWidget", provider: RemoteProvider()) { entry in
            RemoteWidgetContent(entry: entry)
        }
        .configurationDisplayName("Samsung TV Remote")
        .description("Quick controls for your paired Samsung TV.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SamsungTVRemoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        SamsungTVRemoteWidget()
    }
}
