// Common/ActionUIError+Foundation.swift
/*
 On Apple, ActionUIError's localizedDescription is its message, as it was for the NSError it
 replaces (LocalizedError is Foundation's, not FoundationEssentials').
*/

import Foundation

extension ActionUIError: LocalizedError {
    public var errorDescription: String? { message }
}
