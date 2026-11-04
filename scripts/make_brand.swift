// Writes the brand's logo files into brand/ from the same geometry as the app (Sources/NXBiblioteca/LogoGeometry.swift).
// Built like make_icon.swift: copied to main.swift and compiled with LogoGeometry.swift (make_app.sh --brand does it).
import Foundation

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let box = CGRect(x: 0, y: 0, width: 100, height: 100)
let body = LogoGeometry.svgPathData(LogoGeometry.squircle(in: box))
let wave = LogoGeometry.svgPathData(LogoGeometry.wave(in: box))
let stroke = String(format: "%.1f", LogoGeometry.waveWidth * 100)

func svg(_ fill: String, _ waveColor: String, gloss: Bool) -> String {
    let defs = gloss ? """
      <defs>
        <linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1A2D3B"/><stop offset="1" stop-color="#06141B"/></linearGradient>
        <radialGradient id="h" cx=".5" cy="-.3" r=".85"><stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
      </defs>

    """ : ""
    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="512" height="512">
    \(defs)  <path d="\(body)" fill="\(gloss ? "url(#b)" : fill)"/>
    \(gloss ? "  <path d=\"\(body)\" fill=\"url(#h)\"/>\n" : "")  <path d="\(wave)" fill="none" stroke="\(waveColor)" stroke-width="\(stroke)" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>

    """
}

let files = [
    ("logo.svg", svg("#06141B", "#FFFFFF", gloss: true)),
    ("logo-flat.svg", svg("#06141B", "#FFFFFF", gloss: false)),
    ("logo-inverse.svg", svg("#FFFFFF", "#06141B", gloss: false)),
]
for (name, text) in files { try! text.write(to: out.appendingPathComponent(name), atomically: true, encoding: .utf8) }
print("brand: \(files.map(\.0).joined(separator: ", "))")
