import Foundation

// MARK: - ADT object browser DTOs
// Field names match the abaper-ts REST contracts exactly.

/// `/objects/search` → data.Objects[]
struct ADTSearchData: Decodable {
    let objects: [ADTObject]
    enum CodingKeys: String, CodingKey { case objects = "Objects" }
}

struct ADTObject: Decodable, Identifiable, Hashable {
    let name: String
    let type: String
    let description: String?
    let package: String?

    var id: String { "\(type):\(name)" }
}

/// `/packages/contents` → data.nodes[] (objects and sub-packages mixed)
struct PackageContents: Decodable {
    let nodes: [PackageNode]
}

struct PackageNode: Decodable, Identifiable, Hashable {
    let name: String
    let type: String
    let description: String?
    let expandable: Bool?
    let uri: String?

    var id: String { "\(type):\(name)" }

    /// Sub-packages are expandable (DEVC); everything else is a leaf object.
    var isPackage: Bool {
        expandable == true || type.uppercased().hasPrefix("DEVC")
    }
}

/// `/objects/list` → data[] (packages only)
struct ADTPackageSummary: Decodable, Identifiable, Hashable {
    let name: String
    let description: String?

    var id: String { name }
}

/// `/objects/get` → data { object_name, object_type, source, etag }
struct ADTSourceCode: Decodable {
    let objectName: String?
    let objectType: String?
    let source: String
    let etag: String?

    enum CodingKeys: String, CodingKey {
        case objectName = "object_name"
        case objectType = "object_type"
        case source
        case etag
    }
}

// MARK: - Browser selection (navigation value)

struct ObjectRef: Hashable {
    let objectType: String
    let objectName: String
    var functionGroup: String?
    var description: String?
}

struct PackageRef: Hashable {
    let name: String
}
