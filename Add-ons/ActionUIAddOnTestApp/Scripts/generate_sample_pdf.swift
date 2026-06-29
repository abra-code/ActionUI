// Generates the multi-page PDF previewed by the ActionUIAddOnTestApp QuickLook demo, used to
// exercise Quick Look's embedded page scroller. Not part of the app build (Scripts/ is not a
// source dir); run it by hand to (re)generate the committed Resources/Sample.pdf:
//
//   cd Add-ons/ActionUIAddOnTestApp
//   swift Scripts/generate_sample_pdf.swift Resources/Sample.pdf
//
// Each page has a "Page N of M" label and a distinct background tint so scrolling between pages is
// visually obvious.

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sample.pdf"
let pages = 6
let size = CGSize(width: 612, height: 792)   // US Letter

let data = NSMutableData()
guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
    print("error: could not create PDF consumer"); exit(1)
}
var mediaBox = CGRect(origin: .zero, size: size)
guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
    print("error: could not create PDF context"); exit(1)
}

for page in 1...pages {
    ctx.beginPDFPage(nil)
    let gctx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx

    let hue = CGFloat(page - 1) / CGFloat(pages)
    NSColor(hue: hue, saturation: 0.10, brightness: 1.0, alpha: 1.0).setFill()
    NSRect(origin: .zero, size: size).fill()

    let title = "Page \(page) of \(pages)" as NSString
    title.draw(at: CGPoint(x: 64, y: size.height - 150),
               withAttributes: [.font: NSFont.boldSystemFont(ofSize: 52),
                                .foregroundColor: NSColor.black])

    let body = "ActionUIQuickLook multi-page PDF sample.\n\nScroll down in the embedded Quick Look\npreview to reach the next page." as NSString
    body.draw(in: NSRect(x: 64, y: 110, width: size.width - 128, height: size.height - 300),
              withAttributes: [.font: NSFont.systemFont(ofSize: 24),
                               .foregroundColor: NSColor.darkGray])

    NSGraphicsContext.restoreGraphicsState()
    ctx.endPDFPage()
}
ctx.closePDF()

do {
    try data.write(to: URL(fileURLWithPath: outPath))
    print("Wrote \(pages)-page PDF -> \(outPath)")
} catch {
    print("error: \(error)"); exit(1)
}
