# UI philosophy: standard components only

**Use native SwiftUI components and system-provided styling exclusively —
do not invent bespoke design elements.** Reach for what Apple's own apps
(Music, News, Mail, Notes, Settings) do with stock SwiftUI: `List`,
`NavigationStack`, `Label`, `ContentUnavailableView`, `.searchable()`,
`Tab(role: .search)`, system text styles, system colors/materials via
Dynamic Type. No custom color palettes or bespoke card chrome.

- **iPad**: `TabView` with `.tabViewStyle(.sidebarAdaptable)` at the root
  (`RootTabView.swift`) collapses tabs to a bottom bar on iPhone and a
  left sidebar on iPad for free. Each tab is a plain `NavigationStack`
  with push navigation (`NavigationLink(value:)` +
  `.navigationDestination(for:)`) — don't nest a second
  `NavigationSplitView` inside a tab, it fights the outer sidebar.
- **Known accepted limitation, don't re-attempt:** large titles don't
  render properly in a tab's content column under `.sidebarAdaptable`
  (confirmed unsupported by an Apple DTS engineer, Apple Developer Forums
  thread 771704; related toolbar-title gap bug in thread 770969). Several
  workarounds were tried (manual heading view, blanked system title,
  hiding the nav bar, size-class-conditional mixes) and each traded one
  visual bug for another. Settled on the simplest option: plain
  `.navigationTitle(title)` on a `List`, accept whatever the system
  renders. Only revisit if a future SDK changes this.
- **Known accepted limitation, don't re-attempt: the iOS 26 search-tab
  morph doesn't happen here, and it isn't this app's fault.**
  `Tab(role: .search)` is supposed to widen into the search field when
  selected. It doesn't — and the tell is that **the tab bar renders as
  Liquid Glass while the navigation bar and its search field render in
  the iOS 18 style**, the documented signature of the navigation bar not
  receiving the new SDK's adoption. Ruled out: every combination of
  `.searchable` placement, `.tabViewStyle(.sidebarAdaptable)` removed,
  the sort toolbar item removed, the deployment target (already
  `.iOS("26.0")`), and any UIKit appearance proxy (there is none). Then
  the decisive test: **a brand-new empty `.swiftpm` App Project with
  nothing but Apple's canonical `Tab(role: .search)` + `NavigationStack`
  + `.searchable` doesn't morph either.** So it's the Swift Playgrounds
  toolchain, and `.swiftpm` projects can't edit Info.plist, so there is no
  intervention point (compare: IceCubes, built with Xcode 26, behaves
  correctly on the same iPad). This is why `SearchTabView` keeps
  `.navigationBarDrawer(displayMode: .always)` — the drawer is what
  actually renders, so pinning it open is the right adaptation.
  **The large-title bug above may share this root cause** — both are
  navigation bar failures in the same process. Recheck both together if a
  future Swift Playgrounds release changes the rendering.
- **Tapping a carousel card grows it into the detail screen**, via the
  stock `.matchedTransitionSource(id:in:)` /
  `.navigationTransition(.zoom(sourceID:in:))` pair — the App Store's
  card-to-page transition. No custom animation code; the interactive
  pinch-to-dismiss back gesture comes with it.
  `Utilities/PaperTransition.swift` holds both halves as
  `.paperTransitionSource(_:)` and `.paperZoomTransition(_:)`.
  - **`PaperCardView` and `HeadlineView` zoom; `PaperRowView`
    deliberately doesn't.** A card is a bounded, rounded, elevated
    object and a headline is a fixed-height column of newsprint boxed in
    by rules, so growing either into a screen reads as opening the thing
    you touched. A `List` row is full-width and chrome-less, and its
    disclosure chevron already promises a push — so it gets the plain
    push it promises.
  - **That's why `PaperDetailView` is registered under two navigation
    values.** A destination can't tell what pushed it, so the zoom can't
    be applied conditionally from inside it — and **a `.zoom` whose
    source id isn't registered doesn't fall back to a push; the screen
    pops in from nothing** (seen on device). A carousel card pushes
    `ZoomedPaper`; every list row pushes a plain `Paper`. Both land on
    the same screen.
  - **`.zoom` is not the web's View Transitions API, and the source has
    to be the whole card.** It scales the source's rectangle up to the
    full destination and cross-fades — it does not pair elements across
    the push. Anchoring it to just the title (tried, confirmed broken on
    device) makes the title inflate to fill the screen and fly off, then
    the detail screen fades in from nothing. SwiftUI has no
    shared-element morph to reach for instead: `matchedGeometryEffect`
    doesn't cross a `NavigationStack` push. Don't re-attempt.
  - The namespace travels in the environment, for the same reason
    `paperOrigin` does: the push is a plain `NavigationLink(value:)` deep
    inside a shared row, and which stack it belongs to is context, not
    something a row should be handed. **Same placement rule, too — on the
    `NavigationStack`, never on a view inside it.** One `@Namespace` per
    stack (Search, Library, Explore, and the History sheet); every pushed
    screen inherits it, so the carousels on `PaperDetailView` and the
    "See All" lists get it for free.
  - It's `Namespace.ID?` because `Namespace.ID` has no initializer. A
    screen with no namespace installed — a `#Preview`, or a future stack
    that hasn't opted in — falls back to the standard push instead of
    failing to compile or animating wrongly. The source half is also
    inert for papers with no INSPIRE record: those rows open the web
    instead of pushing, so there's no destination to pair with.
- Exceptions to "standard components only", each narrowly scoped:
  - `TightLabelStyle` (`Extensions/LabelStyle+Tight.swift`): custom
    `LabelStyle` tightening `Label`'s icon-to-title spacing at small text
    styles like `.caption`, where the default `.titleAndIcon` style
    reserves an oversized icon slot.
  - `MathTextView` (`Views/Shared/MathTextView.swift`): SwiftUI/UIKit
    have no native math typesetting, and INSPIRE titles/abstracts contain
    LaTeX (`$...$`, `\(...\)`, `$$...$$`, `\[...\]`) or, in some
    publisher-sourced JATS abstracts, literal MathML (`<math>...</math>`).
    Wraps a transparent, self-sizing `WKWebView` running a typesetter
    from CDN — the same approach arXiv.org/inspirehep.net use.
    **Which typesetter is picked per string: KaTeX normally, MathJax only
    when `String.containsMathML` says so.** KaTeX takes TeX input only, so
    the small slice of abstracts carrying a literal `<math>` element need
    MathJax's `tex-mml-svg.js`. KaTeX is roughly 8× lighter on the wire
    and synchronous, where MathJax adds an async startup promise chain —
    which matters because **the cost of this screen is the number of
    `WKWebView`s, and that number can't be reduced** (see
    `AdaptiveMathText`). KaTeX supports less of LaTeX, so
    `throwOnError: false` is paired with `errorColor` set to the body
    colour: INSPIRE abstracts do contain author-defined macros, and this
    degrades them to plain source text rather than MathJax-style red.
    Verified by generating the real HTML and rendering it in a browser:
    `p_T`, `M_W`, `E_T^{\rm miss}`, `\frac`, `\int`, `<sup>`, JATS
    wrappers and both plain and namespaced MathML all typeset, with the
    right engine each time. **The view itself is web-view plumbing and
    nothing else.** The page is `MathDocument` (`Utilities/MathDocument.swift`)
    and its body is `String.mathRenderingHTML`
    (`Extensions/String+MathMarkup.swift`) — both `Foundation`-only, so
    they're the half of this feature that can be generated, diffed and
    rendered in a real browser from a Linux dev machine. `MathWebView`
    resolves the platform-shaped inputs (font point size, colour scheme)
    into plain values and hands them over, so `MathDocument` stays a pure
    function. Supports an optional `lineLimit:` (CSS `-webkit-line-clamp`)
    for row use; height always comes from measured content, never a
    precomputed fixed value. Needs network access and on-device
    verification. **It keeps its touches** — `PaperDetailView` uses it
    directly, isn't inside a button, and its abstract has to stay
    selectable so it can be copied or translated. The opt-out lives on
    `AdaptiveMathText`; see there. **Its measured height also arrives
    asynchronously**, after KaTeX's web fonts load, which is fine in a
    `List` (self-sizing cells stay anchored) and ruinous in a
    `LazyVStack` — see [New](new.md).
  - `AdaptiveMathText` (`Views/Shared/AdaptiveMathText.swift`) +
    `String.containsMathMarkup` (`Extensions/String+MathMarkup.swift`):
    a `WKWebView` per row is expensive and `List` recreates offscreen
    rows while scrolling, so this checks for math delimiters first and
    falls back to plain `Text` when there's none (the common case),
    reserving `MathTextView` for when it's actually needed. Used by
    `PaperRowView`/`PaperCardView` for exactly that scroll-performance
    reason. `PaperDetailView`'s title/abstract skip the check and use
    `MathTextView` directly instead — it's a single screen (no scroll-
    reuse cost), and HEP titles/abstracts essentially always contain
    LaTeX, so the check rarely saves anything there anyway.
    `MathWebView.updateUIView` also skips reloading when the generated
    HTML hasn't changed, since SwiftUI re-invokes it on unrelated
    parent re-renders too.
    **This is also where math text stops taking touches, which is why
    the split matters beyond scroll performance.** A `WKWebView` is a
    real UIKit view and takes the touch, so typeset text inside a
    `Button` swallows the tap — found on device as "tapping a headline's
    abstract doesn't open the paper". `.allowsHitTesting(false)` belongs
    here, where every call site is inside something tappable, and *not*
    on `MathTextView`, which the detail screen uses directly and needs
    selectable. Putting it on the wrong one of the two broke exactly that.
    It takes one `textStyle` (plus an optional `weight`) rather than a
    `Font` *and* a `Font.TextStyle`: the two paths need the value in
    different forms, and asking each call site to say it twice and keep
    the two in agreement was a standing invitation to drift.
    The plain-`Text` branch still runs `String.resolvingInlineMarkup`:
    text needing no math typesetting can still carry `<sup>` or `<i>`,
    which a bare `Text` renders as literal angle brackets. `<sup>`/`<sub>`
    become Unicode (`N³LO`, `⁹⁴Zr`) rather than triggering a web view —
    a superscript isn't worth a web process.
    **Converting the rows' LaTeX to Unicode to avoid the web view
    entirely was measured and rejected. Don't re-attempt.** With a
    generous whitelist (Greek, arrows, relations, `\mathrm`/`\text`
    unwrapping, `\sqrt`, `\bar`), only ~40% of TeX-carrying abstracts
    converted fully, because Unicode structurally can't do it: **no
    uppercase subscripts**, which rules out `p_T`, `M_W`, `E_T` — the
    most common notation in the field — and no way to put a command
    inside a script (`_{\rm eff}`, `_{\odot}`). Making each web view
    cheap (KaTeX) beat making them fewer.
  - **INSPIRE text is markup, not plain text, and it's four different
    kinds of markup**: LaTeX (most titles/abstracts), MathML (rare,
    sometimes namespaced as `<mml:math>`), presentational HTML (`<sup>`,
    `<i>`, `<p>`, `<ul>`, rare), and JATS wrappers from a publisher's XML
    (`<inline-formula>`, `<tex-math notation="LaTeX">$…$</tex-math>`, a
    slice of abstracts). The last three are rare, but unhandled they show
    up as raw `<sup>3</sup>` on screen, which is worse than any of them
    being absent. `mathRenderingHTML` therefore isn't an escape — it's a
    policy: MathML passes through with any namespace prefix stripped (an
    HTML parser reads `<mml:math>` as an element literally named
    "mml:math", which MathJax never finds); presentational tags pass
    through without their attributes, costing MathJax nothing; **any
    other well-formed tag is dropped while its contents are kept**, which
    is what unwraps the JATS wrappers and hands the `$…$` inside straight
    to MathJax; everything else is escaped as before. Dropping rather
    than escaping is right for this data — a `<` that forms a
    well-formed tag is always markup, never something an author typed.
  - `FigureCarouselView` (`Views/Detail/FigureCarouselView.swift`): the
    plots INSPIRE extracts from a paper (`metadata.figures[]`, public,
    unauthenticated PNGs at `inspirehep.net/files/…`), as a full-bleed
    horizontal strip between the title block and the abstract — where the
    App Store puts screenshots. Fixed-size cards so the strip doesn't
    reflow as each image arrives, `AsyncImage` for loading, `LazyHStack`
    so a many-figure paper only fetches what's scrolled to. The card's
    backdrop is a literal `Color.white`, not a semantic color: plots are
    line art on transparent/white and would be unreadable on a dark
    card. Captions aren't shown (they're full LaTeX, often a paragraph);
    they're the accessibility label. Entries whose caption starts with
    `noimg:` are dropped in `InspireRecord` — they're tables recorded as
    figures, and the file behind them is a blank placeholder.
    `Paper.summary` drops figures, so they aren't stored in the library.
    Tapping one opens it full-screen in Quick Look, sharing the single
    `previewURL`/`previewItems` presentation with the PDF button rather
    than installing a second `.quickLookPreview`. Quick Look pages between
    items with a swipe, but only over real files handed to it up front,
    so one tap downloads the whole set via
    `Utilities/TemporaryDownload.swift` (shared with the PDF button):
    concurrent, reassembled in strip order so a swipe matches what's on
    screen, reusing anything already fetched this session. That's why
    there's no custom zoomable image view.
  - PDF viewing (`PaperDetailView.downloadAndPreviewPDF()`): downloads
    the arXiv PDF to a temp file and presents it with `.quickLookPreview
    (_:)` (QuickLook framework) — same in-app preview as Mail/Files,
    instead of the browser or a custom viewer.
  - `PaperCardView` (`Views/Shared/PaperCardView.swift`): a compact,
    abstract-less card sized for horizontal carousels, since a full
    `PaperRowView` doesn't fit side by side. Used for the References/
    Cited By/Related carousels on `PaperDetailView`, mirroring Music's
    "You Might Also Like" row — cards in the shared `cardChrome()`
    material sitting on a `secondarySystemBackground` panel, in a
    horizontal `ScrollView`. The panel isn't a `List` — a
    `NavigationLink` inside a `List` row gets an auto-added disclosure
    chevron on top of any drawn here, and `List` mis-manages multiple
    sibling `NavigationLink`s sharing one row.
- **The card material lives in one place**, `.cardChrome()`
  (`Views/Shared/CardChrome.swift`): `systemBackground` fill, hairline
  `separator` border, radius 14, a soft shadow. `PaperCardView`,
  `BrowseTileView`, `AuthorTileView` and the Related placeholder all wear
  it, which is what makes "the carousel and the grids read as one screen
  made of one thing" true by construction rather than by four hand-kept
  copies — and it's why Home could add a shelf of people without adding a
  design vocabulary. The two surfaces that hold *plots*
  (`FigureCarouselView`, `HeadlineView`'s thumbnail) deliberately don't:
  they're a literal white, because line art on transparency has to
  survive dark mode.
- Likewise `KickerText` (`Views/Shared/KickerText.swift`) — the tinted,
  uppercased line over a title that four screens draw. Only the size
  varies (a card's is `.caption2`), and the detail header is the one that
  passes `lineLimit: nil`, having the width to wrap a long collaboration
  name.
- The detail screen's abstract carries a **Translate** button, presenting
  `.translationPresentation` (the Translation framework's system sheet —
  the same one Safari and Mail show, no key and no networking of ours).
  It's handed `resolvingInlineMarkup` rather than the raw record, so a
  translator isn't shown `<inline-formula>`; inline LaTeX passes through
  untouched. Selecting the text by hand still works and reaches the same
  sheet — the button is a shortcut, not a replacement, which is why
  `MathTextView` must stay hit-testable there.
- The Library tab's toolbar holds the two app-level entry points, as one
  `ToolbarItemGroup`: History (`clock.arrow.circlepath`) and Settings
  (`gearshape`), each a sheet. Settings
  (`Views/Settings/SettingsView.swift`) is a plain `Form` like
  Settings.app — cache size + "Clear Cache" + cache-budget picker, and an
  About section — rather than a tab of its own, the way Music keeps its
  account button in a corner.
- Tabs mirror Apple Music's redesign: `Home` / `New` / `Explore` /
  `Library` as regular tabs, plus `Tab(role: .search)` for search
  (native expand/collapse behavior, not custom animation).
- All user-facing strings are English.
