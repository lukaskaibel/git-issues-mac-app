import Testing
@testable import GitIssuesKit

@Suite("Three-way merge of descriptions")
struct Diff3Tests {
    @Test func unchangedSidesReturnTheOther() {
        #expect(Diff3.merge(base: "a\nb", mine: "a\nb", theirs: "a\nB") == "a\nB")
        #expect(Diff3.merge(base: "a\nb", mine: "A\nb", theirs: "a\nb") == "A\nb")
        #expect(Diff3.merge(base: "a\nb", mine: "x", theirs: "x") == "x")
    }

    @Test func editsToDifferentLinesMerge() {
        let base = "one\n\ntwo\n\nthree"
        let mine = "one\n\ntwo\n\nthree (mine)"
        let theirs = "one (theirs)\n\ntwo\n\nthree"
        #expect(Diff3.merge(base: base, mine: mine, theirs: theirs) == "one (theirs)\n\ntwo\n\nthree (mine)")
    }

    @Test func insertionsAtDifferentPlacesMerge() {
        let base = "a\nb\nc\nd\ne"
        let mine = "start\na\nb\nc\nd\ne"
        let theirs = "a\nb\nc\nd\ne\nend"
        #expect(Diff3.merge(base: base, mine: mine, theirs: theirs) == "start\na\nb\nc\nd\ne\nend")
    }

    @Test func editsToTheSameLineConflict() {
        #expect(Diff3.merge(base: "a\nb\nc", mine: "a\nmine\nc", theirs: "a\ntheirs\nc") == nil)
    }

    @Test func adjacentEditsConflictRatherThanGuess() {
        #expect(Diff3.merge(base: "a\nb\nc\nd", mine: "a\nB\nc\nd", theirs: "a\nb\nC\nd") == nil)
    }

    @Test func windowsLineEndingsDoNotCountAsChanges() {
        // GitHub stores text edited on the web with CRLF; the app edits with LF.
        let base = "one\r\n\r\ntwo\r\n\r\nthree"
        let mine = "one\n\ntwo\n\nthree (mine)"
        let theirs = "one (theirs)\r\n\r\ntwo\r\n\r\nthree"
        #expect(Diff3.merge(base: base, mine: mine, theirs: theirs) == "one (theirs)\n\ntwo\n\nthree (mine)")
    }
}
