# WeBox iOS UI design contract

## Source and scope

Existing product source: https://github.com/zhangx16/Webox-IOS, local reference checkout `/root/Webox-IOS-reference`. The user supplied this earlier project as a source of useful patterns for the whole app; it is not a requirement to reproduce every old UI detail. This revision keeps the current codebase and extracts the earlier app's discover/source switching/recent/favorites structure, blue accent, semantic grouped surfaces and compact poster rhythm.

Native implementation: SwiftUI, dynamic system appearance, four primary tabs (发现 / 收藏 / 下载 / 设置), explicit source management and configuration, source filtering, global search, recent progress, full browse and detail. History is reachable from 收藏 and discover's continue-watching section.

The preview is a self-contained HTML translation of the same design, not an actual iOS screenshot. JS libraries and runtime data are not executed by this preview. Its three user-named JS sources are fixture labels only, and Big Buck Bunny is the existing public demo. The sample progress is visibly marked as a sample. No fabricated movie catalogue or successful site/network results are displayed.

## Tokens and source mapping

| Token | Value / source |
| --- | --- |
| --gap | 16 px, earlier discover horizontal padding and shared 8/16 pt rhythm |
| --fs | 16 px body; native uses scalable SwiftUI semantic text styles |
| --ratio | 1.25, hierarchy mapping rather than literal old 11/12/13/16/26 sizes |
| --measure | 56 ch, caps prose/empty state widths |
| --radius | 16 px main container; 12 px media/control radius derived as 0.75 × main; chips/circle from earlier app |
| --hue | 263, source's blue family; exact accessible accent is --accent |
| --ink | 12% light / 94% dark; semantic primary native ink |
| --surface | 96% light / 12% dark; system grouped background equivalent |
| --line | 88% light / 28% dark; structural tab divider only |
| --edge | 1 px source selection / divider |
| --shadow | 0 at rest; a single floating modal shadow |
| --room | 1.75 × gap, section separation |
| --dur / --ease | 160 ms / cubic-bezier(.2,0,0,1), no focal decorative animation; reduced motion switches off |

Blue ink is darkened from the original accent RGB (0.106,0.451,0.980) to #195edb on light surfaces to meet small-text contrast, with #529eff on dark surfaces. This is an accessibility correction; imagery and brand icon are unchanged. Main background/card colours map native systemGroupedBackground/secondarySystemGroupedBackground. The HTML uses resolved colours for reproducible offline previews.

The source's multiple card radii (8/10/12) are collapsed to main 16 / media 12 plus capsule/circle shape. A circle is an icon control shape, not another arbitrary radius. Poster images can carry their own colours; they do not decide the UI palette.

## Surfaces and interaction

- Discover: header, global search entry, source chips, catalogue, recent progress.
- Empty/loading/error: explicit preview controls; retry removes the error fixture.
- Import/configuration/search/detail/management: native modal semantics in HTML dialog; Escape closes, visible focus, keyboard controls.
- Native source configuration is an explicit discover/catalog link and browse toolbar action; never requires long press.
- Browser provides source-local search, column adaptation, filters, pagination and actionable error display.
- Detail puts title, source, favourite and primary play before summary/episodes/alternate streams; one tap on an episode resolves and plays.
- Web preview navigation is neutralised into explanatory dialogs; it never visits third-party sources. Source switching is functional and does not pretend to provide downloaded data.

## Stable anchor map

`discover`, `discover/header`, `discover/search`, `discover/sources`, `discover/catalog`, `discover/recent`, `discover/empty`, `navigation`, `dialog`, `preview/states`.

## Review tooling and runtime files

Runtime: index.html, webox-icon.png. During review only: draft-kit.js and `window.DRAFT_KIT` block. The release preview `preview.html` excludes that review tooling and fixture state controls. Screenshots/audit JSON are recorded separately.

Native screenshots must come from the iOS CI UI smoke test; HTML screenshots are explicitly labelled as design previews. Design audit does not establish native video playback or website compatibility.

## Automated review executed

Browser: local Chromium via Playwright, offline file URLs, widths 375 / 390 / 767 / 768 / 1024, light and dark. All ten width/theme combinations showed no horizontal overflow and no automatic contrast failures. audit.json is the exact capture; PNGs are HTML design previews. No browser server was started. Native simulator screenshots were not produced by this preview audit.
