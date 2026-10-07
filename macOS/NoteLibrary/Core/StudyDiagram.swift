import Foundation
import CoreGraphics

// Declarative geometry only: no model-supplied markup, scripts or remote resources.
struct StudyDiagram: Codable, Equatable {
    var axes: Bool
    var xLabel: String
    var yLabel: String
    var elements: [DiagramElement]

    func validate() throws {
        guard xLabel.count <= 50, yLabel.count <= 50, (1...40).contains(elements.count) else { throw invalid }
        for item in elements {
            guard ["curve", "line", "arrow", "point", "label", "box"].contains(item.kind),
                  ["primary", "secondary", "muted"].contains(item.style), item.label.count <= 100,
                  !item.points.isEmpty, item.points.count <= 24,
                  item.points.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isFinite && (0...100).contains($0) } }) else { throw invalid }
            switch item.kind {
            case "curve": guard item.points.count == 4 else { throw invalid }
            case "point", "label": guard item.points.count == 1 else { throw invalid }
            case "box": guard item.points.count == 2, item.points[0][0] < item.points[1][0], item.points[0][1] < item.points[1][1] else { throw invalid }
            default: guard item.points.count >= 2, item.points[item.points.count - 2] != item.points.last! else { throw invalid }
            }
        }
        if axes && elements.contains(where: { $0.label.range(of: "^PPC[₀₁₂₃₄₅₆₇₈₉0-9]*$", options: [.regularExpression, .caseInsensitive]) != nil }) {
            for curve in elements where curve.kind == "curve" {
                let p = curve.points
                guard p[0][0] == 0, p[3][1] == 0, p[0][1] > 0, p[3][0] > 0,
                      (1..<4).allSatisfy({ p[$0][0] >= p[$0-1][0] && p[$0][1] <= p[$0-1][1] }) else {
                    throw AppFailure(message: "PPC 图示的边界或弯曲方向不完整，草稿已保留。")
                }
            }
        }
    }
    private var invalid: AppFailure { AppFailure(message: "示意图的结构不完整，草稿已保留。") }
    var accessibleDescription: String { ([xLabel, yLabel] + elements.map(\.label)).filter { !$0.isEmpty }.joined(separator: "；") }

    // Coordinate values describe layout (0...100), never inferred measurements.
    static let width: CGFloat = 700
    static let height: CGFloat = 410
    static func position(_ p: [Double]) -> CGPoint { CGPoint(x: 66 + p[0] * 5.52, y: 344 - p[1] * 2.72) }
    static func arrowhead(from: CGPoint, to: CGPoint) -> [CGPoint] {
        let angle = atan2(to.y - from.y, to.x - from.x)
        return [CGPoint(x: to.x - 9 * cos(angle - 0.48), y: to.y - 9 * sin(angle - 0.48)), to,
                CGPoint(x: to.x - 9 * cos(angle + 0.48), y: to.y - 9 * sin(angle + 0.48))]
    }
    static func labelPosition(_ item: DiagramElement) -> CGPoint {
        let p = position(item.points.last!)
        if item.kind == "box" { let a = position(item.points[0]); return CGPoint(x: (a.x + p.x) / 2, y: (a.y + p.y) / 2) }
        if item.kind == "point" { return CGPoint(x: p.x + 12, y: p.y - 15) }
        return p
    }

    func svg(title: String) -> String {
        guard (try? validate()) != nil else { return "" }
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
        func n(_ value: CGFloat) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(value)) }
        func pair(_ point: CGPoint) -> String { "\(n(point.x)),\(n(point.y))" }
        func label(_ text: String, at p: CGPoint, color: String = "#334942") -> String {
            "<text x='\(n(p.x))' y='\(n(p.y))' fill='\(color)' text-anchor='middle' dominant-baseline='central' font-family='-apple-system, sans-serif' font-size='16'>\(esc(text))</text>"
        }
        var body = "<svg xmlns='http://www.w3.org/2000/svg' role='img' aria-label='\(esc(title))' viewBox='0 0 700 410'><title>\(esc(title))</title>"
        if axes {
            body += "<path d='M66 52 L66 344 L640 344 M61 62 L66 52 L71 62 M630 339 L640 344 L630 349' fill='none' stroke='#697b74' stroke-width='1.8'/>"
            body += label("0", at: CGPoint(x: 53, y: 362)) + label(xLabel, at: CGPoint(x: 548, y: 382)) + label(yLabel, at: CGPoint(x: 94, y: 30))
        }
        for item in elements {
            let points = item.points.map(Self.position)
            let color = item.style == "primary" ? "#16816c" : item.style == "secondary" ? "#727ca7" : "#89918d"
            let stroke = "fill='none' stroke='\(color)' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'" + (item.dashed ? " stroke-dasharray='6 5'" : "")
            switch item.kind {
            case "curve": body += "<path d='M\(pair(points[0])) C\(points.dropFirst().map(pair).joined(separator: " "))' \(stroke)/>"
            case "line", "arrow":
                body += "<polyline points='\(points.map(pair).joined(separator: " "))' \(stroke)/>"
                if item.kind == "arrow" { body += "<polyline points='\(Self.arrowhead(from: points[points.count-2], to: points.last!).map(pair).joined(separator: " "))' \(stroke)/>" }
            case "point": body += "<circle cx='\(n(points[0].x))' cy='\(n(points[0].y))' r='4' fill='\(color)'/>"
            case "box": body += "<rect x='\(n(points[0].x))' y='\(n(points[1].y))' width='\(n(points[1].x-points[0].x))' height='\(n(points[0].y-points[1].y))' rx='9' fill='#f1f6f3' stroke='\(color)' stroke-width='1.5'/>"
            default: break
            }
            if !item.label.isEmpty { body += label(item.label, at: Self.labelPosition(item)) }
        }
        return body + "</svg>"
    }

    static var schema: [String: Any] {
        func object(_ properties: [String: Any]) -> [String: Any] { ["type": "object", "additionalProperties": false, "properties": properties, "required": Array(properties.keys).sorted()] }
        let string: [String: Any] = ["type": "string"]
        let element = object(["kind": ["type": "string", "enum": ["curve", "line", "arrow", "point", "label", "box"]], "label": string, "style": ["type": "string", "enum": ["primary", "secondary", "muted"]], "dashed": ["type": "boolean"], "points": ["type": "array", "items": ["type": "array", "items": ["type": "number"]]]])
        return object(["axes": ["type": "boolean"], "xLabel": string, "yLabel": string, "elements": ["type": "array", "items": element]])
    }
}

struct DiagramElement: Codable, Equatable {
    var kind: String
    var label: String
    var style: String
    var dashed: Bool
    var points: [[Double]]
}
