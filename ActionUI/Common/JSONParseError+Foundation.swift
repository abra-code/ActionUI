// Common/JSONParseError+Foundation.swift
/*
 On Apple, a JSONParseError's localizedDescription is the sentence JSONDecoder's DecodingError
 gave, the error it replaces (Core/Helpers/JSONParser.swift), so a document that does not parse
 still reads "Failed to load view: The data couldn't be read because it isn't in the correct
 format." in a LoadableView. The parser's own message, with the byte offset, is its description,
 for logs and the adapters' last error. LocalizedError is Foundation's, not FoundationEssentials'.
*/

import Foundation

extension JSONParseError: LocalizedError {
    var errorDescription: String? { "The data couldn't be read because it isn't in the correct format." }
}
