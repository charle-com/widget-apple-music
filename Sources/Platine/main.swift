import AppKit
import PlatineCore
import PlatineUI
import SwiftUI

// Platine --render <dossier> [--sample] : rend les quatre tailles du widget en PNG, sans passer par le bureau.
// Sert à contrôler le rendu après une modification des vues. Sans --sample, part de l'état réel.
@MainActor
func renderPreviews(to directory: URL, sample: Bool) {
    let now = Date()
    let frame = sample ? Frame.sample(at: now) : Planner.frames(for: SharedStore.load(), now: now)[0]
    let sizes: [(PlatineSize, CGSize)] = [
        (.small, CGSize(width: 170, height: 170)),
        (.medium, CGSize(width: 364, height: 170)),
        (.large, CGSize(width: 364, height: 382)),
        (.extraLarge, CGSize(width: 764, height: 382)),
    ]
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (size, dimensions) in sizes {
        let view = ZStack {
            PlatineBackground(frame: frame)
            PlatineView(frame: frame, size: size, live: false)
        }
        .frame(width: dimensions.width, height: dimensions.height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { continue }
        let rep = NSBitmapImageRep(cgImage: cg)
        let url = directory.appendingPathComponent("\(size.rawValue).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print(url.path)
    }
}

let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--render"), arguments.count > i + 1 {
    let directory = URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
    MainActor.assumeIsolated { renderPreviews(to: directory, sample: arguments.contains("--sample")) }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let coordinator = Coordinator()
    app.delegate = coordinator
    app.setActivationPolicy(.accessory)
    // Le délégué est retenu faiblement par NSApplication : on le garde en vie le temps de run().
    withExtendedLifetime(coordinator) { app.run() }
}
