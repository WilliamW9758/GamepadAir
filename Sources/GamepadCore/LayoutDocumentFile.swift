import Foundation

/// File and marketplace response bodies share exactly the same bounded document decoder.
public enum LayoutDocumentFile {
    public static func read(_ url: URL, provenance: LayoutProvenance? = nil) throws -> LocalLayout {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 256 * 1024 else { throw LayoutDocumentError("Layout file is too large") }
        return try LocalLayout.importDocument(Data(contentsOf: url), provenance: provenance)
    }
    public static func write(_ layout: LocalLayout, to url: URL) throws {
        // This is ordinary JSON, not RFC 8785 bytes. Origin digests are supplied by the
        // publication service and are never recomputed from JSONEncoder output.
        try layout.document.validatedData().write(to: url, options: .atomic)
    }
}

public enum LayoutDocumentDownload {
    /// Download the document body from an immutable revision URL. Authentication and
    /// catalog metadata live outside the document; provenance remains origin-only.
    public static func load(_ url: URL, provenance: LayoutProvenance? = nil, session: URLSession = .shared) async throws -> LocalLayout {
        guard url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")) else {
            throw LayoutDocumentError("Layout downloads require HTTPS")
        }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw LayoutDocumentError("Layout download failed") }
        guard response.expectedContentLength <= LayoutDocument.maximumBytes else { throw LayoutDocumentError("Layout exceeds 256 KiB") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < LayoutDocument.maximumBytes else { throw LayoutDocumentError("Layout exceeds 256 KiB") }
            data.append(byte)
        }
        return try LocalLayout.importDocument(data, provenance: provenance)
    }
}
