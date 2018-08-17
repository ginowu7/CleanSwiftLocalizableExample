#!/usr/bin/swift

import Foundation

let fileManager = FileManager.default
let currentPath = fileManager.currentDirectoryPath

/// List of files in currentPath - recursive
var pathFiles: [String] = {
    guard let enumerator = fileManager.enumerator(atPath: currentPath),
        let files = enumerator.allObjects as? [String]
        else { fatalError("Could not locate files in path directory: \(currentPath)") }
    return files
}()


/// List of localizable files - not including Localizable files in the Pods
var localizableFiles: [String] = {
    let files = pathFiles.filter { $0.hasSuffix("Localizable.strings") && !$0.contains("Pods") }
    return files
}()


/// List of executable files
var executableFiles: [String] = {
    return pathFiles.filter {
        !$0.localizedCaseInsensitiveContains("test") &&
            (NSString(string: $0).pathExtension == "swift" || NSString(string: $0).pathExtension == "m")
    }
}()


/// Reads contents in path
///
/// - Parameter path: path of file
/// - Returns: content in file
func contents(atPath path: String) -> String {
    guard let data = fileManager.contents(atPath: path),
        let content = String(data: data, encoding: .utf8)
        else { fatalError("Could not read from path: \(path)") }
    return content
}


/// Returns a list of strings that match regex pattern from content
///
/// - Parameters:
///   - pattern: regex pattern
///   - content: content to match
/// - Returns: list of results
func regexFor(_ pattern: String, content: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { fatalError("Regex not formatted correctly: \(pattern)")}
    let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
    return matches.map {
        guard let range = Range($0.range(at: 0), in: content) else { fatalError("Incorrect range match") }
        return String(content[range])
    }
}

func create() -> [LocalizationStringsFile] {
    return localizableFiles.map(LocalizationStringsFile.init(path:))
}

/// Makes sure all localizable files contain the same keys
///
/// - Parameter files: list of localizable files to validate
func validateKeys(_ files: [LocalizationStringsFile]) {
    guard let base = files.first, files.count > 1 else { return }
    let files = Array(files.dropFirst())
    files.forEach {
        guard let extraKey = Set(base.keys).symmetricDifference($0.keys).first else { return }
        let incorrectFile = $0.keys.contains(extraKey) ? $0 : base
        fatalError("Found extra key: \(extraKey) in file: \(incorrectFile.path)")
    }
}

///
///
/// - Returns: A list of LocalizationCodeFile - contains path of file and all keys in it
func localizedStringsInCode() -> [LocalizationCodeFile] {
    let files = executableFiles
    return files.map {
        let content = contents(atPath: $0)
        let matches = regexFor("(?<=NSLocalizedString\\()\\s*\"(.*?)\"", content: content)
        return LocalizationCodeFile(path: $0, keys: Set(matches))
    }
}


/// Checks for defined keys in code, not defined in localizable strings file
///
/// - Parameters:
///   - codeFiles: Array of LocalizationCodeFile
///   - localizationFiles: Array of LocalizableStringFiles
func validateKeys(_ codeFiles: [LocalizationCodeFile], localizationFiles: [LocalizationStringsFile]) {
    guard let baseFile = localizationFiles.first else { return }
    let baseKeys = Set(baseFile.keys)
    codeFiles.forEach {
        let extraKeys = $0.keys.subtracting(baseKeys)
        if !extraKeys.isEmpty { print("Found keys in code: \(extraKeys), not defined in strings file ") }
    }
}

protocol Pathable {
    var path: String { get }
}

struct LocalizationStringsFile: Pathable {
    let path: String
    let kv: [String: String]

    var keys: [String] {
        return Array(kv.keys)
    }

    init(path: String) {
        let kv = ContentParser.parse(path)
        self.path = path
        self.kv = kv
    }

    func cleanWrite() {
        let content = kv.keys.sorted().map { "\($0) = \(kv[$0]!);" }.joined(separator: "\n")
        try! content.write(toFile: path, atomically: true, encoding: .utf8)
    }

}

struct LocalizationCodeFile: Pathable {
    let path: String
    let keys: Set<String>
}

enum ContentParser {
    static func parse(_ path: String) -> [String: String] {
        let content = contents(atPath: path)

        let trimmed = content
            .replacingOccurrences(of: "\n+", with: "", options: .regularExpression, range: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let keys = regexFor("\"([^\"]*?)\"(?= =)", content: trimmed)
        let values = regexFor("(?<== )\"(.*?)\"(?=;)", content: trimmed)
        if keys.count != values.count { fatalError("Error parsing contents") }
        return zip(keys, values).reduce(into: [String: String]()) { results, keyValue in
            if results[keyValue.0] != nil { fatalError("Found duplicate key: \(keyValue.0) in file: \(path)") }
            results[keyValue.0] = keyValue.1
        }
    }
}

let files = create()
validateKeys(files)
files.forEach { $0.cleanWrite() }

let codeFiles = localizedStringsInCode()
validateKeys(codeFiles, localizationFiles: files)
