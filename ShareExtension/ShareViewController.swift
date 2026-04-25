import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

/// Share Extension entry point.
/// Receives archive files shared from Files, Mail, Safari, etc. and
/// hands them off to the main app via a shared app-group container.
final class ShareViewController: UIViewController {

    // Derived at runtime so resigners (e.g. SideStore/AltStore) that rewrite
    // the bundle ID don't break the share-extension ↔ main-app handoff.
    // Extension bundle ID is "<main-id>.shareextension"; strip the last component.
    private var appGroupIdentifier: String {
        let id = Bundle.main.bundleIdentifier ?? "com.yourcompany.unarchiver.shareextension"
        let mainID = id.split(separator: ".").dropLast().joined(separator: ".")
        return "group.\(mainID)"
    }

    // MARK: - Life cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        showSpinner()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        processSharedItems()
    }

    // MARK: - Processing

    private func processSharedItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            done(error: "No items to open")
            return
        }

        let supportedTypes: [String] = [
            UTType.zip.identifier,
            UTType.gzip.identifier,
            "public.tar-archive",
            "public.gzip-archive",
            "org.gnu.gnu-tar-gzip-archive",
            "org.gnu.gnu-zip-archive",
            "org.bzip2.bzip2-archive",
            "public.bzip2-archive",
            "public.plain-text",
            "public.text",
            "public.source-code",
            "public.script",
            "public.shell-script",
            "public.json",
            "public.xml",
            "public.yaml",
            "public.data",          // fallback for unrecognised types
        ]

        for item in items {
            for provider in (item.attachments ?? []) {
                for typeId in supportedTypes {
                    if provider.hasItemConformingToTypeIdentifier(typeId) {
                        loadItem(provider: provider, typeId: typeId)
                        return
                    }
                }
            }
        }
        done(error: "No supported archive found in share")
    }

    private func loadItem(provider: NSItemProvider, typeId: String) {
        // loadFileRepresentation always yields a file URL regardless of how the
        // provider internally represents the data (URL, Data, cloud file, etc.).
        // The temp file is only valid for the duration of the closure, so the
        // copy to the shared container must happen synchronously here.
        provider.loadFileRepresentation(forTypeIdentifier: typeId) { [weak self] tempURL, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.done(error: error.localizedDescription) }
                return
            }
            guard let tempURL else {
                DispatchQueue.main.async { self.done(error: "Could not obtain file URL") }
                return
            }
            // Some providers (e.g. Mail) store items as a binary plist wrapping a
            // file URL rather than writing actual file bytes to the temp location.
            // Resolve to the real file before copying.
            let sourceURL = self.resolveBplistURL(tempURL) ?? tempURL

            let fm = FileManager.default
            guard let containerURL = fm.containerURL(
                forSecurityApplicationGroupIdentifier: self.appGroupIdentifier) else {
                DispatchQueue.main.async { self.done(error: "Could not obtain file URL") }
                return
            }
            let destURL = containerURL.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                _ = sourceURL.startAccessingSecurityScopedResource()
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: sourceURL, to: destURL)
                sourceURL.stopAccessingSecurityScopedResource()
            } catch {
                sourceURL.stopAccessingSecurityScopedResource()
                DispatchQueue.main.async {
                    self.done(error: "Could not save shared file: \(error.localizedDescription)")
                }
                return
            }
            DispatchQueue.main.async { self.openMainApp(fileURL: destURL) }
        }
    }

    /// If `url` points to a binary plist wrapping a file URL (a Mail quirk),
    /// returns the wrapped URL; otherwise returns nil.
    private func resolveBplistURL(_ url: URL) -> URL? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.prefix(6) == Data("bplist".utf8) else { return nil }

        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        // Mail encodes ["file:///...", "", {}] — grab the first string element.
        if let array = plist as? [Any],
           let str = array.first as? String,
           let resolved = URL(string: str) { return resolved }

        // Simple plist string
        if let str = plist as? String,
           let resolved = URL(string: str) ?? URL(fileURLWithPath: str) as URL? { return resolved }

        // NSKeyedArchive of NSURL
        if let nsurl = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) {
            return nsurl as URL
        }

        // URL bookmark data
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: .withoutUI,
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private func openMainApp(fileURL: URL) {
        // Store the URL in shared UserDefaults so the main app can pick it up
        UserDefaults(suiteName: appGroupIdentifier)?
            .set(fileURL.absoluteString, forKey: "pendingFileURL")

        // Build the URL scheme call: unarchiver://open?path=<encoded>
        var components = URLComponents()
        components.scheme = "unarchiver"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "path", value: fileURL.absoluteString)
        ]

        guard let appURL = components.url else {
            done(error: nil)
            return
        }

        // Open the main app
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(appURL, options: [:]) { [weak self] _ in
                    self?.done(error: nil)
                }
                return
            }
            responder = responder?.next
        }

        // If we couldn't find UIApplication, just dismiss
        done(error: nil)
    }

    // MARK: - UI helpers

    private func showSpinner() {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func done(error: String?) {
        if let error {
            let containerAvailable = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil
            let diagnostics = """
                \(error)

                — Extension bundle: \(Bundle.main.bundleIdentifier ?? "unknown")
                — App group: \(appGroupIdentifier)
                — Container: \(containerAvailable ? "available" : "unavailable")
                """
            let alert = UIAlertController(title: "Cannot Open",
                                          message: diagnostics,
                                          preferredStyle: .alert)
            alert.addAction(.init(title: "OK", style: .default) { [weak self] _ in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            })
            present(alert, animated: true)
        } else {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
