// Sources/Layout/SteadyTitleWidth.swift
/*
 The width a row lays its title out with when its content starts after the title (LabeledContent,
 TitledControlLayout), and a Form's label column reads (FormColumn).

 A TextBlock's own width can come back a pixel apart from one measure to the next (13 then 12.5 points
 at 200%, measured on Windows 11; by WinUI's source, a text's width is rounded up to the pixel grid of
 the scale it finds, which may differ between passes). The content would then start at a different place
 each pass, which lays the row out again: with a TextBox in the window, WinUI stopped on a layout cycle.
 So the width is rounded up to a whole point, and a new width within a point of the last one keeps the
 larger of the two: it settles after one more pass at any scale and is never narrower than the text.
*/

struct SteadyTitleWidth {
    private var kept: Double?

    /// The width to lay the title out with, for a title that measured `measured` wide now.
    mutating func width(_ measured: Double) -> Double {
        var width = measured.rounded(.up)
        if let kept, abs(width - kept) <= 1 {
            width = max(width, kept)
        }
        kept = width
        return width
    }

    /// Forgets the last width: the title's text changed.
    mutating func reset() {
        kept = nil
    }
}
