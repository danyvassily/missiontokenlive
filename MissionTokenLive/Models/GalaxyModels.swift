
import Foundation

/// Galaxie gbrain : agrégat de ce que le cerveau contient, sans jamais exposer de texte long.
struct Galaxy: Codable {
    let available: Bool
    let facts: Int
    let sources: Int
    let entities: Int
    let nodes: [GalaxyNode]
    let edges: [GalaxyEdge]

    static let empty = Galaxy(available: false, facts: 0, sources: 0, entities: 0, nodes: [], edges: [])
}

struct GalaxyNode: Codable, Identifiable {
    let id: String
    let label: String
    let kind: String   // core | source | entity | fact
    let weight: Int
}

struct GalaxyEdge: Codable {
    let a: Int
    let b: Int
}
