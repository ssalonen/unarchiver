import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

/// Share Extension entry point.
/// Receives archive files shared from Files, Mail, Safari, etc. and
/// hands them off to the main app via a shared app-group container.
final class ShareViewController: UIViewController {

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
            "public.data",          // fallback for unrecognised archive types
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
        provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] item, error in
            DispatchQueue.main.async {
                if let error {
                    self?.done(error: error.localizedDescription)
                    return
                }
                if let url = item as? URL {
                    self?.copyToSharedContainer(url: url)
                } else if let data = item as? Data {
                    // Some providers (e.g. cloud storage) deliver file bytes directly
                    // rather than a URL; write to a temp file and proceed normally.
                    let filename = provider.suggestedName ?? "archive.zip"
                    self?.writeDataToTemp(data: data, filename: filename)
                } else {
                    self?.done(error: "Could not obtain file URL")
                }
            }
        }
    }

    private func writeDataToTemp(data: Data, filename: String) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent(filename)
            try data.write(to: tempURL)
            copyToSharedContainer(url: tempURL)
        } catch {
            done(error: "Could not save shared file: \(error.localizedDescription)")
        }
    }

    private func copyToSharedContainer(url: URL) {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.yourcompany.unarchiver") else {
            // Fallback: open directly if app group is not configured
            openMainApp(fileURL: url)
            return
        }

        let destURL = containerURL.appendingPathComponent(url.lastPathComponent)
        do {
            _ = url.startAccessingSecurityScopedResource()
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)
            url.stopAccessingSecurityScopedResource()
            openMainApp(fileURL: destURL)
        } catch {
            url.stopAccessingSecurityScopedResource()
            // Try to open the original URL directly
            openMainApp(fileURL: url)
        }
    }

    private func openMainApp(fileURL: URL) {
        // Store the URL in shared UserDefaults so the main app can pick it up
        UserDefaults(suiteName: "group.com.yourcompany.unarchiver")?
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
            let alert = UIAlertController(title: "Cannot Open",
                                          message: error,
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
