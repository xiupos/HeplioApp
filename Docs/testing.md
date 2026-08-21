# Testing approach

SwiftUI can't build on this Linux dev machine, so model/networking changes
are verified by copying the relevant `Foundation`-only files into a
scratch SwiftPM executable (`swift run`) exercised against the **real**
INSPIRE API (not mocks) — e.g. decoding live responses, or firing rapid
requests to confirm the rate limiter avoids 429s. Delete the scratch
package after. UI-level verification (layout, navigation, animations) has
to happen in Swift Playgrounds on-device and should be called out as
unverified when it hasn't been checked there.

**Anything that generates HTML can go further than that: render it.**
`MathDocument` is `Foundation`-only precisely so a scratch executable can
write its real output to disk, serve it, and check the result in a
browser — which is how the KaTeX switch was confirmed (`p_T`, `\frac`,
`<sup>`, JATS wrappers and both plain and namespaced MathML all typeset,
each by the intended engine). Inspect the DOM rather than eyeballing a
screenshot: counting `.katex` / `mjx-container` nodes and reading back
`innerText` says exactly what happened. **Copy the real file in; never
retype the template into the test.** An earlier round did that and the
copy is what a refactor then has to keep in sync — which is half the
reason the document moved out of the view.
