import Foundation

/// One `/`-separated part of a VS Code glob: `**` (any number of folders) or a
/// name pattern with `*`, `?` and `[...]` / `[!...]` character sets.
///
/// `*` and `?` never cross a `/`, and both match a leading dot, as in VS Code.
struct FileExplorerGlobSegment: Sendable, Equatable {
    private enum Token: Sendable, Equatable {
        case literal(Character)
        case anyCharacter
        case anyRun
        case set(negated: Bool, members: [ClosedRange<Character>])

        func matches(_ character: Character) -> Bool {
            switch self {
            case .literal(let expected):
                return character == expected
            case .anyCharacter:
                return true
            case .anyRun:
                return false
            case .set(let negated, let members):
                return members.contains { $0.contains(character) } != negated
            }
        }
    }

    /// `**`: matches zero or more whole path parts.
    let isGlobstar: Bool
    private let tokens: [Token]

    init(_ text: String) {
        if text == "**" {
            isGlobstar = true
            tokens = []
            return
        }
        isGlobstar = false
        tokens = Self.tokens(of: Array(text))
    }

    /// Whether `name`, one path part, matches this segment.
    func matches(_ name: String) -> Bool {
        if isGlobstar {
            return true
        }
        let characters = Array(name)
        // Wildcard matching with one backtrack point, linear in practice.
        var token = 0
        var index = 0
        var starToken = -1
        var starIndex = 0
        while index < characters.count {
            if token < tokens.count, tokens[token] != .anyRun, tokens[token].matches(characters[index]) {
                token += 1
                index += 1
            } else if token < tokens.count, tokens[token] == .anyRun {
                starToken = token
                starIndex = index
                token += 1
            } else if starToken >= 0 {
                token = starToken + 1
                starIndex += 1
                index = starIndex
            } else {
                return false
            }
        }
        while token < tokens.count, tokens[token] == .anyRun {
            token += 1
        }
        return token == tokens.count
    }

    private static func tokens(of characters: [Character]) -> [Token] {
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "*":
                // `**` inside a name (`foo**`) means the same as `*`.
                if tokens.last != .anyRun {
                    tokens.append(.anyRun)
                }
                index += 1
            case "?":
                tokens.append(.anyCharacter)
                index += 1
            case "[":
                if let (set, next) = characterSet(in: characters, openingAt: index) {
                    tokens.append(set)
                    index = next
                } else {
                    tokens.append(.literal(character))
                    index += 1
                }
            default:
                tokens.append(.literal(character))
                index += 1
            }
        }
        return tokens
    }

    /// Parses `[...]` starting at `start`; nil when the bracket never closes.
    private static func characterSet(in characters: [Character], openingAt start: Int) -> (Token, Int)? {
        var index = start + 1
        var negated = false
        if index < characters.count, characters[index] == "!" || characters[index] == "^" {
            negated = true
            index += 1
        }
        var members: [ClosedRange<Character>] = []
        var first = true
        while index < characters.count {
            let character = characters[index]
            // A `]` right after the opening bracket is a member, not the end.
            if character == "]", !first {
                return (.set(negated: negated, members: members), index + 1)
            }
            first = false
            if index + 2 < characters.count, characters[index + 1] == "-", characters[index + 2] != "]",
               character <= characters[index + 2] {
                members.append(character...characters[index + 2])
                index += 3
            } else {
                members.append(character...character)
                index += 1
            }
        }
        return nil
    }
}
