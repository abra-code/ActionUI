// Common/ActionUIInsertion.swift
//
// Types and errors used by ActionUIModel.insertElement / insertRow / removeElement.
// Containers declare which containers accept runtime insertions via ActionUIViewConstruction.insertableContainers.

import Foundation

// Position to insert a new element (or row) within a container's existing array.
// `before(siblingID:)` and `after(siblingID:)` apply only to flat containers — for row containers,
// rows have no synthetic identity, so use `at(_:)`, `append`, or `prepend`.
public enum InsertPosition {
    case append
    case prepend
    case at(Int)
    case before(siblingID: Int)
    case after(siblingID: Int)
}

// Shape of a container container. Determines whether the container holds a flat array of elements
// (children, destinations, toolbar, commands, columns) or a 2-D array of element rows
// (Grid's `rows`).
public enum ContainerShape {
    case flat
    case rows
}

// Errors thrown by insertElement / insertRow / removeElement.
public enum InsertError: Error, CustomStringConvertible {
    case windowNotFound(String)
    case parentNotFound(parentID: Int)
    case notAContainer(type: String)
    case unknownContainer(container: String, vaildContainers: [String])
    case containerRequired(vaildContainers: [String])
    case wrongMethod(container: String, expectedShape: ContainerShape, message: String)
    case unsupportedPositionForRowContainer(container: String)
    case positionOutOfBounds(index: Int, count: Int)
    case siblingNotFound(siblingID: Int, container: String)
    case idConflict(ids: [Int])
    case invalidJSON(String)
    case missingType
    case rootRemovalForbidden(rootID: Int)
    case viewNotFound(viewID: Int)
    case viewIsRowMember(viewID: Int)

    public var description: String {
        switch self {
        case .windowNotFound(let uuid):
            return "No WindowModel for windowUUID: \(uuid)"
        case .parentNotFound(let id):
            return "No element found with parentID \(id)"
        case .notAContainer(let type):
            return "Element type '\(type)' does not accept insertions (no insertableContainers declared)"
        case .unknownContainer(let container, let valid):
            return "Unknown container '\(container)'. Valid containers: \(valid.joined(separator: ", "))"
        case .containerRequired(let valid):
            return "container is required when the container exposes multiple containers: \(valid.joined(separator: ", "))"
        case .wrongMethod(let container, let expectedShape, let message):
            return "Container '\(container)' has shape \(expectedShape); \(message)"
        case .unsupportedPositionForRowContainer(let container):
            return "Row container '\(container)' does not support before/after sibling positions; rows have no addressable identity"
        case .positionOutOfBounds(let i, let count):
            return "Position \(i) is out of bounds for container of size \(count)"
        case .siblingNotFound(let id, let container):
            return "No element with id \(id) found in container '\(container)'"
        case .idConflict(let ids):
            return "ID conflict — elements with these IDs are already registered: \(ids)"
        case .invalidJSON(let detail):
            return "Invalid JSON: \(detail)"
        case .missingType:
            return "Element dictionary missing 'type' key"
        case .rootRemovalForbidden(let id):
            return "Cannot remove root element (id \(id))"
        case .viewNotFound(let id):
            return "No element found with viewID \(id)"
        case .viewIsRowMember(let id):
            return "viewID \(id) is a Grid cell — removing it removes only the cell, not its row. Rows are not addressable by id."
        }
    }
}
