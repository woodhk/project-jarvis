import Foundation
import Testing
@testable import JarvisCore

/// Writes session history files the way Claude Code does: one compact JSON record per line.
final class HistoryBench {
    let dir: URL
    init() throws { dir = try tempDir() }

    func file(_ session: String) -> URL { dir.appendingPathComponent("\(session).jsonl") }

    func append(_ session: String, _ records: [[String: Any]], endWithNewline: Bool = true) throws {
        var text = (try? String(contentsOf: file(session), encoding: .utf8)) ?? ""
        let lines = try records.map { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.withoutEscapingSlashes]), as: UTF8.self) }
        text += lines.joined(separator: "\n") + (endWithNewline ? "\n" : "")
        try text.write(to: file(session), atomically: true, encoding: .utf8)
    }

    func reply(_ text: String) -> [String: Any] {
        ["type": "assistant", "isSidechain": false, "message": ["role": "assistant", "content": [["type": "text", "text": text]]]]
    }
}

@Suite struct ReplyGistBuilderTests {
    /// Session P is about agent patterns, Q about a shop. Both talk about "the script".
    func twoSessions() throws -> HistoryBench {
        let b = try HistoryBench()
        try b.append("P", [
            b.reply("The script opens with the augmented LLM, then moves to workflows and agents."),
            b.reply("Beat two: workflows are fixed paths. Agents choose their own. The augmented LLM is the base of both."),
            b.reply("I tightened the script: the augmented LLM line, then workflows, then agents."),
            ["type": "user", "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1", "content": "zebra zebra zebra crossing"]]]],
            ["type": "assistant", "message": ["role": "assistant", "content": [["type": "tool_use", "id": "t1", "name": "Read", "input": ["file_path": "/work/zebra/crossing.md"]]]]],
            ["type": "api-request-blob", "message": ["content": [["type": "text", "text": "giraffe giraffe giraffe giraffe"]]], "note": "\"type\":\"assistant\""],
            ["type": "assistant", "isSidechain": true, "message": ["role": "assistant", "content": [["type": "text", "text": "hippo hippo hippo from a helper"]]]],
        ])
        try b.append("Q", [
            b.reply("The checkout page has a new cart drawer. The script that builds it is unchanged."),
            b.reply("Cart drawer done; checkout page next. I ran the script again."),
        ])
        return b
    }

    @Test func theTopicOfASessionComesFromClaudesReplies() throws {
        let b = try twoSessions()
        let g = ReplyGistBuilder(userNames: ["sam"]).gists(historyFiles: ["P": b.file("P"), "Q": b.file("Q")])
        let p = try #require(g["P"]), q = try #require(g["Q"])
        #expect(p.contains("augmented llm"))
        #expect(p.contains("workflows"))
        #expect(p.contains("agents"))
        #expect(q.contains("cart drawer"))
        #expect(!q.contains("workflows"))
        #expect(p.first != "script" && q.first != "script")            // a word both sessions use says little about either
        #expect(p.count <= 20)
    }

    @Test func onlyClaudesOwnWordsCount() throws {
        let b = try twoSessions()
        let all = try #require(ReplyGistBuilder(userNames: []).gists(historyFiles: ["P": b.file("P")])["P"]).joined(separator: " ")
        #expect(!all.contains("zebra"))                                  // tool results and tool inputs (file contents, paths)
        #expect(!all.contains("giraffe"))                                // request blobs repeat the conversation
        #expect(!all.contains("hippo"))                                  // helper agents' messages
    }

    @Test func privateTextAndCodeAreLeftOut() throws {
        let b = try HistoryBench()
        try b.append("S", [
            b.reply("Sam, the report is at https://x.test/report and in /Users/sam/reports/final.md. Mail sam@x.test when the invoice table is ready."),
            b.reply("The invoice table is ready.\n```swift\nfunc secretHandshake() { let tokenValue = 1 }\n```\nNext: the invoice totals."),
        ])
        let all = try #require(ReplyGistBuilder(userNames: ["sam"]).gists(historyFiles: ["S": b.file("S")])["S"]).joined(separator: " ")
        #expect(all.contains("invoice"))
        for banned in ["sam", "http", "users", "x.test", "handshake", "tokenvalue"] { #expect(!all.contains(banned), "\(banned)") }
    }

    @Test func onlyNewLinesAreReadWhenAFileGrows() throws {
        let b = try twoSessions()
        let builder = ReplyGistBuilder(userNames: [])
        _ = builder.gists(historyFiles: ["P": b.file("P"), "Q": b.file("Q")])
        #expect(builder.bytesRead > 0)
        let before = builder.bytesRead
        #expect(builder.gists(historyFiles: ["P": b.file("P"), "Q": b.file("Q")])["P"]?.contains("workflows") == true)
        #expect(builder.bytesRead == before)                             // nothing changed: nothing is read again

        let size = (try FileManager.default.attributesOfItem(atPath: b.file("Q").path)[.size] as? Int) ?? 0
        try b.append("Q", [b.reply("Now the refund form. The refund form needs a reason field."), b.reply("Refund form shipped.")], endWithNewline: false)
        let grown = try #require(builder.gists(historyFiles: ["P": b.file("P"), "Q": b.file("Q")])["Q"])
        let newSize = (try FileManager.default.attributesOfItem(atPath: b.file("Q").path)[.size] as? Int) ?? 0
        #expect(builder.bytesRead - before < newSize - size + 8)        // only the added part, not the whole file
        #expect(grown.contains("cart drawer"))                           // the earlier part still counts
        #expect(!grown.joined(separator: " ").contains("shipped"))       // the last line has no line end yet: it may still be being written
        try b.append("Q", [], endWithNewline: true)
        let finished = try #require(builder.gists(historyFiles: ["P": b.file("P"), "Q": b.file("Q")], top: 40)["Q"]).joined(separator: " ")
        #expect(finished.contains("shipped"))
        #expect(finished.contains("refund form"))
    }

    @Test func aSessionWithoutRepliesOrWithoutAFileHasNoGist() throws {
        let b = try HistoryBench()
        try b.append("E", [["type": "user", "message": ["role": "user", "content": "hello"]]])
        let g = ReplyGistBuilder(userNames: []).gists(historyFiles: ["E": b.file("E"), "missing": b.file("missing")])
        #expect(g["E"] == nil)
        #expect(g["missing"] == nil)
    }

    // From the real sessions: the topic words of a session ("agents", "workflows") are also said in other open
    // sessions, so by distinctiveness alone they lost to rare phrases. Half of the gist is now the most used words.
    @Test func theMostUsedWordsStayEvenWhenAnotherSessionSaysThemToo() throws {
        let b = try HistoryBench()
        var replies: [[String: Any]] = (1...6).map { b.reply("Agents and workflows again, beat number \(["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"][$0 - 1]) here.") }
        replies += ["quartz lantern", "velvet harbor", "copper meadow", "silver thicket", "amber glacier", "ivory canyon"].flatMap { pair in
            [b.reply("A note on the \(pair)."), b.reply("More on the \(pair).")]
        }
        try b.append("P", replies)
        try b.append("Q", [b.reply("Agents came up once."), b.reply("Workflows came up once."), b.reply("Mostly the checkout page.")])
        try b.append("R", [b.reply("The garden plan."), b.reply("The garden plan again.")])
        let p = try #require(ReplyGistBuilder(userNames: []).gists(historyFiles: ["P": b.file("P"), "Q": b.file("Q"), "R": b.file("R")], top: 6)["P"])
        #expect(p.contains { $0.contains("agents") })                     // alone or as part of a pair
        #expect(p.contains { $0.contains("workflows") })
        #expect(p.contains { $0.contains("quartz") || $0.contains("velvet") || $0.contains("copper") })     // distinctive ones are still there
    }

    // The user allowed this on 2026-11-11: a session's topic is often in the documents Claude wrote there
    // (241 mentions against 14 in its replies, in the session that was not found).
    @Test func documentsClaudeWroteCountToo() throws {
        let b = try HistoryBench()
        func tool(_ name: String, _ input: [String: Any]) -> [String: Any] {
            ["type": "assistant", "message": ["role": "assistant", "content": [["type": "tool_use", "id": "t", "name": name, "input": input]]]]
        }
        try b.append("D", [
            b.reply("Draft two is in the doc."),
            tool("mcp__claude_ai_Claude_Docs__update", ["ref": ["object": "node", "id": "n1"], "payload": ["markdown": "Beat one: the augmented LLM. Beat two: workflows versus agents."]]),
            tool("mcp__claude_ai_Claude_Docs__update", ["ref": ["object": "node", "id": "n2"], "payload": "Hook: an augmented LLM is not an agent. Workflows come first."]),
            tool("Write", ["file_path": "/work/reel/script-draft.md", "content": "Scene: the augmented LLM picks a tool. Then workflows, then agents."]),
            tool("Edit", ["file_path": "/work/reel/notes.txt", "old_string": "walrus walrus", "new_string": "Workflows are fixed paths; agents decide."]),
            tool("Write", ["file_path": "/work/reel/render.swift", "content": "let pelicanCount = 3 // pelican pelican pelican"]),
            tool("Bash", ["command": "echo ostrich ostrich ostrich", "description": "say ostrich ostrich"]),
        ])
        let all = try #require(ReplyGistBuilder(userNames: []).gists(historyFiles: ["D": b.file("D")], top: 20)["D"]).joined(separator: " | ")
        #expect(all.contains("augmented llm"))
        #expect(all.contains("workflows"))
        for skipped in ["pelican", "ostrich", "walrus", "script-draft"] { #expect(!all.contains(skipped), "\(skipped)") }
    }
}
