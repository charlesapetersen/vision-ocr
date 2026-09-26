import PDFKit
import Foundation

// pdfkit-lines — what a reader can select, line by line, as PDFKit (Preview) sees it.
//
//   pdfkit-lines <pdf> [page…]                   each line: x y width height | text
//   pdfkit-lines --diff <before.pdf> <after.pdf> [page…]
//                                                per page: line and word counts, then
//                                                each line only one side has (- / +)
//
// Pages are 1-indexed; the default is every page. Built for C33, where poppler
// (`pdftotext -bbox`) found a word box over every printed line on pages whose lines
// PDFKit dropped or printed as junk, so a poppler reading cannot stand in for this.
// It reads `page.selection(for: mediaBox).selectionsByLine()`, the same lines a drag
// selection walks. `--diff` is how C33 checked that a change to recognition lost no
// line anywhere in a document: every `-` line should be junk the `+` lines replace.
//
// Build: swiftc -O -o /tmp/pdfkit-lines Tools/pdfkit-lines.swift
// Exit: 0 ok · 1 a PDF will not open · 2 usage.

func usage() -> Never {
    FileHandle.standardError.write("usage: pdfkit-lines <pdf> [page…] | --diff <before.pdf> <after.pdf> [page…]\n"
        .data(using: .utf8)!)
    exit(2)
}

func openPDF(_ path: String) -> PDFDocument {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
        FileHandle.standardError.write("pdfkit-lines: cannot open \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    return doc
}

func pages(_ args: ArraySlice<String>, of doc: PDFDocument) -> [Int] {
    if args.isEmpty { return Array(1...max(1, doc.pageCount)).filter { $0 <= doc.pageCount } }
    return args.map { a -> Int in
        guard let n = Int(a), n >= 1, n <= doc.pageCount else { usage() }
        return n
    }
}

/// The page's selectable lines, top to bottom as PDFKit orders them.
func lines(of doc: PDFDocument, page n: Int) -> [(bounds: CGRect, text: String)] {
    guard let page = doc.page(at: n - 1),
          let all = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
    return all.selectionsByLine().map {
        ($0.bounds(for: page),
         ($0.string ?? "").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces))
    }.filter { !$0.text.isEmpty }
}

let args = CommandLine.arguments.dropFirst()
guard let first = args.first else { usage() }

if first == "--diff" {
    guard args.count >= 3 else { usage() }
    let before = openPDF(args[args.startIndex + 1]), after = openPDF(args[args.startIndex + 2])
    for n in pages(args.dropFirst(3), of: before) {
        let a = lines(of: before, page: n).map(\.text)
        let b = n <= after.pageCount ? lines(of: after, page: n).map(\.text) : []
        let words = { (l: [String]) in l.reduce(0) { $0 + $1.split(separator: " ").count } }
        print("p\(n): \(a.count) -> \(b.count) lines, words \(words(a)) -> \(words(b))")
        // As multisets, so a line printed twice, or one of two identical lines
        // lost, still shows.
        var surplus = [String: Int]()
        for l in a { surplus[l, default: 0] += 1 }
        for l in b { surplus[l, default: 0] -= 1 }
        var shown = [String: Int]()
        for l in a where shown[l, default: 0] < (surplus[l] ?? 0) {
            shown[l, default: 0] += 1
            print("  - \(l)")
        }
        for l in b where shown[l, default: 0] < -(surplus[l] ?? 0) {
            shown[l, default: 0] += 1
            print("  + \(l)")
        }
    }
    if after.pageCount != before.pageCount {
        print("page count \(before.pageCount) -> \(after.pageCount)")
    }
} else {
    let doc = openPDF(first)
    for n in pages(args.dropFirst(), of: doc) {
        print("=== page \(n)")
        for l in lines(of: doc, page: n) {
            print(String(format: "%6.1f %6.1f %6.1f %5.1f | ", l.bounds.minX, l.bounds.minY,
                         l.bounds.width, l.bounds.height) + l.text)
        }
    }
}
