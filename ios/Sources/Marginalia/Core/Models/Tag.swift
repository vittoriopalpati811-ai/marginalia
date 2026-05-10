import Foundation
import SwiftData

@Model
final class Tag {
    var id: UUID
    var name: String
    var color: String   // hex

    // Relazione M:M con Highlight (SwiftData usa array su entrambi i lati)
    var highlights: [Highlight] = []

    init(name: String, color: String = "#C4A882") {
        self.id = UUID()
        self.name = name
        self.color = color
    }
}
