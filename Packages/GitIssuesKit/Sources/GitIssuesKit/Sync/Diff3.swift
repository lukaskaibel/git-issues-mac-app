import Foundation

/// Line-based three-way merge, used when a description was edited both locally and on GitHub.
public enum Diff3 {
    struct Hunk: Equatable {
        /// Lines of the base this hunk replaces. Empty for a pure insertion.
        var range: Range<Int>
        var lines: [Substring]
    }

    /// Returns the merged text, or nil when both sides changed the same or adjacent lines.
    public static func merge(base: String, mine: String, theirs: String) -> String? {
        let base = normalize(base), mine = normalize(mine), theirs = normalize(theirs)
        if mine == theirs { return mine }
        if mine == base { return theirs }
        if theirs == base { return mine }

        let b = lines(base)
        let ours = hunks(base: b, other: lines(mine))
        let others = hunks(base: b, other: lines(theirs))

        var output: [Substring] = []
        var position = 0
        var i = 0, j = 0

        func apply(_ hunk: Hunk) {
            output += b[position..<hunk.range.lowerBound]
            output += hunk.lines
            position = hunk.range.upperBound
        }

        while i < ours.count || j < others.count {
            switch (i < ours.count ? ours[i] : nil, j < others.count ? others[j] : nil) {
            case let (a?, c?):
                if a == c {
                    apply(a)
                    i += 1
                    j += 1
                } else if a.range.lowerBound <= c.range.upperBound && c.range.lowerBound <= a.range.upperBound {
                    return nil
                } else if a.range.lowerBound < c.range.lowerBound {
                    apply(a)
                    i += 1
                } else {
                    apply(c)
                    j += 1
                }
            case let (a?, nil):
                apply(a)
                i += 1
            case let (nil, c?):
                apply(c)
                j += 1
            case (nil, nil):
                break
            }
        }
        output += b[position...]
        return output.joined(separator: "\n")
    }

    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
    }

    private static func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// The changes that turn `base` into `other`, as replacements of base line ranges.
    static func hunks(base: [Substring], other: [Substring]) -> [Hunk] {
        let n = base.count, m = other.count
        // Longest common subsequence lengths for suffixes.
        var table = [Int](repeating: 0, count: (n + 1) * (m + 1))
        func at(_ i: Int, _ j: Int) -> Int { i * (m + 1) + j }
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[at(i, j)] = base[i] == other[j]
                        ? table[at(i + 1, j + 1)] + 1
                        : max(table[at(i + 1, j)], table[at(i, j + 1)])
                }
            }
        }
        var result: [Hunk] = []
        var i = 0, j = 0
        var startI = 0, startJ = 0
        func flush(_ endI: Int, _ endJ: Int) {
            if endI > startI || endJ > startJ {
                result.append(Hunk(range: startI..<endI, lines: Array(other[startJ..<endJ])))
            }
        }
        while i < n && j < m {
            if base[i] == other[j] {
                flush(i, j)
                i += 1
                j += 1
                startI = i
                startJ = j
            } else if table[at(i + 1, j)] >= table[at(i, j + 1)] {
                i += 1
            } else {
                j += 1
            }
        }
        flush(n, m)
        return result
    }
}
