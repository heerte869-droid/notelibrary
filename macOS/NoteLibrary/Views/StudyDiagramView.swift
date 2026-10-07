import SwiftUI

struct StudyDiagramView: View {
    let diagram: StudyDiagram
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Canvas { context, size in
            guard (try? diagram.validate()) != nil else { return }
            context.scaleBy(x: size.width / StudyDiagram.width, y: size.height / StudyDiagram.height)
            func label(_ value: String, _ point: CGPoint) {
                context.draw(Text(value).font(.system(size: 16, weight: .medium)).foregroundStyle(colorScheme == .dark ? Color(white: 0.87) : Color(white: 0.24)), at: point)
            }
            func line(_ points: [CGPoint], color: Color, width: CGFloat = 2.6, dashed: Bool = false) {
                var path = Path(); path.addLines(points)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dashed ? [6, 5] : []))
            }
            if diagram.axes {
                line([CGPoint(x: 66, y: 52), CGPoint(x: 66, y: 344), CGPoint(x: 640, y: 344)], color: .secondary, width: 1.8)
                line(StudyDiagram.arrowhead(from: CGPoint(x: 66, y: 90), to: CGPoint(x: 66, y: 52)), color: .secondary, width: 1.8)
                line(StudyDiagram.arrowhead(from: CGPoint(x: 600, y: 344), to: CGPoint(x: 640, y: 344)), color: .secondary, width: 1.8)
                label("0", CGPoint(x: 53, y: 362)); label(diagram.xLabel, CGPoint(x: 548, y: 382)); label(diagram.yLabel, CGPoint(x: 94, y: 30))
            }
            for item in diagram.elements {
                let points = item.points.map(StudyDiagram.position)
                let color: Color = item.style == "primary" ? Theme.accent : item.style == "secondary" ? Color(red: 0.53, green: 0.57, blue: 0.77) : .secondary
                switch item.kind {
                case "curve":
                    var path = Path(); path.move(to: points[0]); path.addCurve(to: points[3], control1: points[1], control2: points[2])
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: item.dashed ? [6, 5] : []))
                case "line", "arrow":
                    line(points, color: color, dashed: item.dashed)
                    if item.kind == "arrow" { line(StudyDiagram.arrowhead(from: points[points.count-2], to: points.last!), color: color) }
                case "point": context.fill(Path(ellipseIn: CGRect(x: points[0].x-4, y: points[0].y-4, width: 8, height: 8)), with: .color(color))
                case "box":
                    let path = Path(roundedRect: CGRect(x: points[0].x, y: points[1].y, width: points[1].x-points[0].x, height: points[0].y-points[1].y), cornerRadius: 9)
                    context.fill(path, with: .color(color.opacity(0.07))); context.stroke(path, with: .color(color.opacity(0.65)), lineWidth: 1.5)
                default: break
                }
                if !item.label.isEmpty { label(item.label, StudyDiagram.labelPosition(item)) }
            }
        }.aspectRatio(StudyDiagram.width / StudyDiagram.height, contentMode: .fit)
            .background(Theme.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .ignore).accessibilityLabel(diagram.accessibleDescription)
    }
}
