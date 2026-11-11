import CoreImage
import CryptoKit
import Foundation
import ImageIO
import PlatineCore
import UniformTypeIdentifiers

/// Télécharge chaque pochette une fois et en tire les quatre fichiers lus par le widget :
/// 600 px, 300 px, vignette 96 px et fond flouté. Le widget ne fait ni réseau ni traitement d'image.
actor ArtworkCache {
    static let shared = ArtworkCache()

    private var inflight: [String: Task<Bool, Never>] = [:]

    static func key(for urlString: String) -> String {
        SHA256.hash(data: Data(urlString.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    static func exists(_ key: String) -> Bool {
        let fm = FileManager.default
        return [SharedStore.ArtSize.large, .medium, .small, .background].allSatisfy {
            fm.fileExists(atPath: SharedStore.artURL(key: key, size: $0).path)
        }
    }

    /// Renvoie la clé de la pochette une fois ses fichiers présents, nil si elle est indisponible.
    func ensure(_ urlString: String) async -> String? {
        guard !urlString.isEmpty else { return nil }
        let key = Self.key(for: urlString)
        if Self.exists(key) { return key }
        if let running = inflight[key] { return await running.value ? key : nil }
        let task = Task.detached(priority: .utility) { await Self.fetch(urlString, key: key) }
        inflight[key] = task
        let ok = await task.value
        inflight[key] = nil
        return ok ? key : nil
    }

    private static func fetch(_ urlString: String, key: String) async -> Bool {
        // Les pochettes Apple Music sont servies à la taille demandée dans l'URL (…/800x800bb.jpg).
        let sized = urlString.replacingOccurrences(of: #"/\d+x\d+bb\."#, with: "/600x600bb.", options: .regularExpression)
        guard let url = URL(string: sized) else { return false }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Platine/1.0 (macOS widget)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }

        try? FileManager.default.createDirectory(at: SharedStore.artDirectory, withIntermediateDirectories: true)
        guard let large = scaled(source, 600), let medium = scaled(source, 300), let small = scaled(source, 96),
              let background = blurred(medium) else { return false }
        return write(large, key, .large, 0.86) && write(medium, key, .medium, 0.86)
            && write(small, key, .small, 0.84) && write(background, key, .background, 0.80)
    }

    private static func scaled(_ source: CGImageSource, _ maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Luminance moyenne visée pour le fond : au-dessus, le texte blanc du widget devient illisible.
    private static let maxBackgroundLuminance = 0.26

    /// Fond du widget : flou large, couleurs plus saturées, et assombri autant qu'il faut pour rester un verre
    /// fumé sombre même sous une pochette blanche.
    private static func blurred(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let context = CIContext()
        var output = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 30)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.45])
            .cropped(to: input.extent)

        let average = output.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: input.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let luminance = (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
        if luminance > maxBackgroundLuminance {
            let k = CGFloat(maxBackgroundLuminance / luminance)
            output = output.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
            ])
        }
        return context.createCGImage(output, from: input.extent)
    }

    private static func write(_ image: CGImage, _ key: String, _ size: SharedStore.ArtSize, _ quality: Double) -> Bool {
        let url = SharedStore.artURL(key: key, size: size)
        let tmp = url.appendingPathExtension("tmp")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return false }
        // Renommage atomique : le widget ne lit jamais une image à moitié écrite.
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Supprime les pochettes qui n'ont pas servi depuis trois semaines.
    static func prune() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: SharedStore.artDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let limit = Date().addingTimeInterval(-21 * 86_400)
        for file in files {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < limit {
                try? fm.removeItem(at: file)
            }
        }
    }
}
