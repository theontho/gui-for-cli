---
output: 'docs.html'
title: 'GUI for CLI documentation map'
description: 'Documentation map for GUI for CLI frontends, bundles, experiments, distribution, and static site generation.'
eyebrow: 'Documentation'
heading: 'Where to go next.'
lede: 'The README now stays focused on the product. Detailed experiment history, architecture notes, distribution flow, and schemas live in dedicated documents.'
actions: 'Open README|https://github.com/theontho/gui-for-cli/blob/main/README.md|primary; Experiment doc|https://github.com/theontho/gui-for-cli/blob/main/docs/desktop-gui-experiments.md'
footer_title: 'Documentation map'
footer_text: 'Product docs stay short; detailed engineering notes stay close to the code.'
---

::: section
::: wrap
::: grid two
::: card
{{ kicker: Product }}
### README
The top-level README describes the two product frontends, setup, common commands, bundles, config, and distribution packaging.

{{ link: Open README|https://github.com/theontho/gui-for-cli/blob/main/README.md|inline-link }}
:::

::: card
{{ kicker: Experiments }}
### Desktop GUI experiments
The moved experiment document explains the renderer inventory, benchmark lessons, and why only `swiftui-macos` and `tauri-webui` are product frontends.

{{ link: Open experiment doc|https://github.com/theontho/gui-for-cli/blob/main/docs/desktop-gui-experiments.md|inline-link }}
:::

::: card
{{ kicker: Architecture }}
### Development architecture
Repository layout, platform runner commands, stable code, experimental code, and AI documentation structure.

{{ link: Open architecture doc|https://github.com/theontho/gui-for-cli/blob/main/docs/ai/development-architecture.md|inline-link }}
:::

::: card
{{ kicker: Distribution }}
### Packaging
Signing, notarization, Tauri packages, SwiftUI DMGs, release artifacts, and embedded bundle defaults.

{{ link: Open distribution doc|https://github.com/theontho/gui-for-cli/blob/main/docs/distribution.md|inline-link }}
:::
:::
:::
:::

::: section
::: wrap
## Generate this site

Edit Markdown in `site_src/`, then run:

```bash
python3 scripts/build_site.py
open site/index.html
```

The generated HTML is written to `site/` and can be served by GitHub Pages.
:::
:::
