# Layout parity fixtures

ActionUI promises that one document lays out the same on every platform. These fixtures check it with numbers: SwiftUI's own layout is recorded once, and every renderer is tested against the recording.

- `fixtures/` - ActionUI documents. Each root has a fixed `frame` (`width` and `height`), which is the size the test lays the document out at. The leaves are `Color` elements, each with its own `"#RRGGBB"` color, so their frames can be read from a picture. They are sized with frames, padding, stacks and `Spacer`s. Text is avoided, because fonts differ between platforms.
- `expected/` - for each fixture, the root's size and each Color's frame (`[x, y, width, height]` in points from the root's top leading corner, keyed by element id), as SwiftUI lays it out on macOS.

## Who checks them

- Apple: `ActionUITests/Views/LayoutParityTests.swift` renders each fixture with the SwiftUI renderer, draws it into a bitmap and reads each Color's frame from its pixels. It checks the frames against `expected/`.
- Linux (GTK): `ActionUIAdwaita/Tests/Layout/LayoutParityTests.swift` lays out each fixture with the GTK renderer and checks the same frames. A fixture GTK does not match yet is listed there with the reason.
- Web: `ActionUITests/Views/WebLayoutParityTests.swift` (on a Mac) renders each fixture with ActionUIWeb in a WKWebView, which loads the web renderer's own files with no server, and reads each Color's frame from the pixels of a snapshot. A fixture the web renderer does not match yet is listed there with its causes.

Frames may differ by up to 1 point: SwiftUI places views at fractions of a point, and GTK places them at whole pixels.

## Recording

After adding a fixture, or when a new macOS changes SwiftUI's layout, record the expected frames on a Mac. Then look at the changes before committing them: a recording is only as good as the SwiftUI it was made with.

```
ACTIONUI_LAYOUT_RECORD=1 swift test --filter ActionUITests.LayoutParityTests
```
