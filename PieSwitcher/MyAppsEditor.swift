import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The "My Apps" list editor (Bringr-93j.40): a curated, manually ordered set of apps
/// that becomes the wheel's default ordering for those apps. Reads and writes the same
/// `CuratedApps` defaults key the wheel reads at summon, so an edit applies on the next
/// open without a relaunch. Deliberately not `@AppStorage`: the value is a JSON-encoded
/// list, not an `@AppStorage`-native scalar, so it lives in `@State` hydrated from
/// `CuratedApps.current()` — this editor is the list's only writer, so a one-time read at
/// view creation stays in sync.
struct MyAppsEditor: View {
    @State private var apps: [CuratedApp] = CuratedApps.current()
    @State private var selection: CuratedApp.ID?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            listBox
            controls
            Text("Pinned apps lead the wheel in this order. Drag app bundles from Finder "
                 + "or the Dock onto the list, or use the + button.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var listBox: some View {
        List(selection: $selection) {
            ForEach(apps) { app in
                MyAppRow(app: app)
            }
            .onMove { indices, destination in
                apps.move(fromOffsets: indices, toOffset: destination)
                persist()
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: 160)
        .overlay {
            if apps.isEmpty {
                Text("No apps yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: isDropTargeted ? 2 : 0)
        }
        .dropDestination(for: URL.self) { urls, _ in
            addBundles(at: urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                addViaPanel()
            } label: {
                Image(systemName: "plus").frame(width: 18)
            }
            .help("Add an app…")

            Button {
                removeSelected()
            } label: {
                Image(systemName: "minus").frame(width: 18)
            }
            .disabled(selection == nil)
            .help("Remove the selected app")

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Native Open panel scoped to applications, defaulting to /Applications, so the
    /// user can pick one or more apps to pin even when they aren't running.
    private func addViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose apps to pin to the wheel"
        guard panel.runModal() == .OK else { return }
        addBundles(at: panel.urls)
    }

    private func addBundles(at urls: [URL]) {
        let updated = CuratedApps.adding(bundlesAt: urls, to: apps)
        guard updated != apps else { return }
        apps = updated
        persist()
    }

    private func removeSelected() {
        guard let id = selection else { return }
        apps.removeAll { $0.id == id }
        selection = nil
        persist()
    }

    private func persist() {
        CuratedApps.save(apps)
    }
}

/// One row in the My Apps editor: the app's Finder icon and display name.
private struct MyAppRow: View {
    let app: CuratedApp

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 18, height: 18)
            Text(app.name)
                .lineLimit(1)
        }
    }

    /// The bundle's Finder icon, or a generic application icon when the app is no
    /// longer installed (a stale entry still shows, so the user can remove it).
    private var icon: NSImage {
        if let url = app.bundleURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}

#Preview {
    MyAppsEditor()
        .padding()
        .frame(width: 460)
}
