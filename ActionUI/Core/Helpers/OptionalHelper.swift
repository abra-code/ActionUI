//
//  OptionalProtocol.swift
//  ActionUI
//
//  Created by Tomasz Kukielka on 3/4/26.
//


protocol OptionalProtocol {
    static var wrappedType: Any.Type { get }
}

extension Optional: OptionalProtocol {
    static var wrappedType: Any.Type { Wrapped.self }
}

func isOptional(_ type: Any.Type) -> Bool {
    return type is OptionalProtocol.Type
}

// get the base type whether it is optional or non-optional,
// e.g.: String?.self becomes String.self

func getNonOptionalType(_ type: Any.Type) -> Any.Type {
    if let optionalType = type as? OptionalProtocol.Type {
        return optionalType.wrappedType
    }
    return type
}
