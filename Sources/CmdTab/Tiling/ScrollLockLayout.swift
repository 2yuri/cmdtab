import CoreGraphics

/// Turns a strip into window frames on one screen. Pure: same input, same frames.
///
/// Frames use the screen's own coordinates with y growing downwards, like Accessibility.
struct ScrollLockLayout<Window: Hashable> {
    struct Options: Equatable {
        var padding: CGFloat
        var gap: CGFloat
        var centreMode: CentreMode
        /// How much more of each tab behind shows past the one in front of it.
        var tabPeek: CGFloat = 16
    }

    /// Tabs further back than this sit right behind the last one shown, so many tabs never squeeze the
    /// one in front.
    static var maximumPeeks: Int { 4 }

    struct Result {
        var frames: [Window: CGRect]
        /// Where each column is, for drag and drop and the strip map.
        var columnFrames: [CGRect]
        /// The strip's horizontal scroll position, kept between layouts so it moves only when needed.
        var scroll: CGFloat
        /// The strip's full width, for the strip map.
        var stripWidth: CGFloat
        /// Each column's position and width along the strip (before scrolling), for the strip map.
        var columnSpans: [(offset: CGFloat, width: CGFloat)] = []
        /// The width of the part of the strip that's on screen.
        var viewWidth: CGFloat = 0
        /// Columns out of view to the left are parked at the right edge (see `parkedSliver`); this is
        /// where they would be, so an animation can slide them out to the left before they jump.
        var slideFrames: [Window: CGRect] = [:]
    }

    /// How much of a window stays on screen when its column is scrolled out of view.
    /// macOS keeps every window at least partly visible, so park it at the right edge.
    static var parkedSliver: CGFloat { 1 }

    let options: Options

    /// - Parameters:
    ///   - screen: the usable area of the screen (no menu bar or Dock), y growing downwards.
    ///   - previousScroll: the last scroll position, so focus moves inside the view don't scroll.
    ///   - followsFocus: false after the user scrolled the strip by hand (⌃⌥ + scroll): keep their position.
    ///   - fixedScroll: an exact scroll position, used for the frames in between while the strip slides.
    ///   - parksBeyondScreen: park a column only once it has left the whole screen, not just the usable
    ///     area, so columns glide through the padding during a scroll instead of popping out.
    ///   - parkingBounds: the whole screen. Columns out of view are parked just past its edges, not the
    ///     usable area's, or they would show in the padding on top of their neighbours.
    func layout(
        _ strip: ScrollLockStrip<Window>,
        in screen: CGRect,
        previousScroll: CGFloat,
        followsFocus: Bool = true,
        parkingBounds: CGRect? = nil,
        fixedScroll: CGFloat? = nil,
        parksBeyondScreen: Bool = false
    ) -> Result {
        let parking = parkingBounds ?? screen
        let usable = screen.insetBy(dx: options.padding, dy: options.padding)
        guard !strip.isEmpty, usable.width > 0, usable.height > 0 else {
            return Result(frames: [:], columnFrames: [], scroll: 0, stripWidth: 0)
        }

        // Widths share the gaps so that three 33% columns fill the screen exactly.
        let widths = strip.columns.map { width(for: $0.width, usableWidth: usable.width) }
        var offsets: [CGFloat] = []
        var x: CGFloat = 0
        for width in widths {
            offsets.append(x)
            x += width + options.gap
        }
        let stripWidth = x - options.gap

        let scroll = fixedScroll ?? (followsFocus ? scrollPosition(
            focused: strip.focusedColumnIndex.map { (offsets[$0], widths[$0]) },
            stripWidth: stripWidth,
            viewWidth: usable.width,
            previous: previousScroll
        ) : clamp(previousScroll, stripWidth: stripWidth, viewWidth: usable.width)) // Hand scrolling stops at the ends.

        var frames: [Window: CGRect] = [:]
        var slideFrames: [Window: CGRect] = [:]
        var columnFrames: [CGRect] = []
        for (index, column) in strip.columns.enumerated() {
            var columnX = usable.minX + offsets[index] - scroll
            let width = widths[index]
            // Fully off screen: park it at the edge, mostly hidden.
            // Out of the usable area: park just past the screen's right edge, mostly hidden. macOS keeps
            // about 40 points of a window on screen past the left edge, but only one past the right.
            var slideX: CGFloat?
            let bounds = parksBeyondScreen ? parking : usable
            if columnX >= bounds.maxX {
                columnX = parking.maxX - Self.parkedSliver
            } else if columnX + width <= bounds.minX {
                slideX = min(columnX, parking.minX - width)
                columnX = parking.maxX - Self.parkedSliver
            }
            let columnFrame = CGRect(x: columnX, y: usable.minY, width: width, height: usable.height)
            columnFrames.append(columnFrame)

            if column.isTabbed {
                // The tab in front is the narrowest; each one behind shows `tabPeek` more on the right.
                let order = strip.tabOrder(of: column)
                let steps = min(order.count - 1, Self.maximumPeeks)
                for (depth, window) in order.enumerated() {
                    let inset = min(CGFloat(max(steps - depth, 0)) * options.tabPeek, width / 2)
                    frames[window] = Self.pixelAligned(CGRect(x: columnX, y: usable.minY, width: width - inset, height: usable.height))
                    if let slideX {
                        slideFrames[window] = Self.pixelAligned(CGRect(x: slideX, y: usable.minY, width: width - inset, height: usable.height))
                    }
                }
                continue
            }

            var y = usable.minY
            let fractions = strip.heightFractions(of: column)
            for (window, fraction) in zip(column.windows, fractions) {
                let height = (usable.height + options.gap) * fraction - options.gap
                frames[window] = Self.pixelAligned(CGRect(x: columnX, y: y, width: width, height: height))
                if let slideX {
                    slideFrames[window] = Self.pixelAligned(CGRect(x: slideX, y: y, width: width, height: height))
                }
                y += height + options.gap
            }
        }
        return Result(
            frames: frames,
            columnFrames: columnFrames,
            scroll: scroll,
            stripWidth: stripWidth,
            columnSpans: Array(zip(offsets, widths)).map { (offset: $0.0, width: $0.1) },
            viewWidth: usable.width,
            slideFrames: slideFrames
        )
    }

    /// Rounds each edge to whole points, so neighbouring windows keep exactly `gap` between them.
    static func pixelAligned(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        return CGRect(x: minX, y: minY, width: rect.maxX.rounded() - minX, height: rect.maxY.rounded() - minY)
    }

    func width(for width: ColumnWidth, usableWidth: CGFloat) -> CGFloat {
        (usableWidth + options.gap) * width.fraction - options.gap
    }

    /// The column whose middle is closest to the middle of the view: where a hand scroll settles.
    static func columnNearestToCentre(of result: Result) -> Int? {
        let centre = result.scroll + result.viewWidth / 2
        return result.columnSpans.indices.min {
            abs(result.columnSpans[$0].offset + result.columnSpans[$0].width / 2 - centre)
                < abs(result.columnSpans[$1].offset + result.columnSpans[$1].width / 2 - centre)
        }
    }

    /// The share of the screen a window `pixels` wide takes, to snap a dragged edge to a preset.
    static func fraction(ofWidth pixels: CGFloat, usableWidth: CGFloat, gap: CGFloat) -> Double {
        Double((pixels + gap) / (usableWidth + gap))
    }

    private func scrollPosition(
        focused: (x: CGFloat, width: CGFloat)?,
        stripWidth: CGFloat,
        viewWidth: CGFloat,
        previous: CGFloat
    ) -> CGFloat {
        guard let focused else { return clamp(previous, stripWidth: stripWidth, viewWidth: viewWidth) }
        let centred = focused.x + focused.width / 2 - viewWidth / 2

        switch options.centreMode {
        case .always:
            return centred
        case .whenOverflowing:
            guard stripWidth > viewWidth else { return 0 }
            return clamp(centred, stripWidth: stripWidth, viewWidth: viewWidth)
        case .never:
            var scroll = previous
            if focused.x < scroll {
                scroll = focused.x
            } else if focused.x + focused.width > scroll + viewWidth {
                scroll = focused.x + focused.width - viewWidth
            }
            return clamp(scroll, stripWidth: stripWidth, viewWidth: viewWidth)
        }
    }

    private func clamp(_ scroll: CGFloat, stripWidth: CGFloat, viewWidth: CGFloat) -> CGFloat {
        min(max(scroll, 0), max(stripWidth - viewWidth, 0))
    }
}
