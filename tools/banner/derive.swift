// Fabrique les quatre fichiers de pochette lus par le widget, avec le même traitement que l'app
// (Sources/Platine/Artwork.swift) : 600 px, 300 px, vignette 96 px, fond flouté plafonné en luminance.
// Usage : swift derive.swift <dossier des png> <dossier art>
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let maxBackgroundLuminance = 0.26

func scaled(_ source: CGImageSource, _ maxPixel: Int) -> CGImage? {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

func blurred(_ image: CGImage) -> CGImage? {
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

func write(_ image: CGImage, _ url: URL, _ quality: Double) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let art = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try? FileManager.default.createDirectory(at: art, withIntermediateDirectories: true)
for file in (try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "png" {
    let key = file.deletingPathExtension().lastPathComponent
    guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
          let large = scaled(src, 600), let medium = scaled(src, 300), let small = scaled(src, 96),
          let background = blurred(medium) else { print("échec \(key)"); continue }
    write(large, art.appendingPathComponent("\(key)-l.jpg"), 0.86)
    write(medium, art.appendingPathComponent("\(key)-m.jpg"), 0.86)
    write(small, art.appendingPathComponent("\(key)-s.jpg"), 0.84)
    write(background, art.appendingPathComponent("\(key)-bg.jpg"), 0.80)
    print(key)
}
