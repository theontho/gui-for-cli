---
output: 'docs.html'
title: 'GUI for CLI documentation map'
description: 'Documentation map for GUI for CLI: the app, bundles, distribution, and static site generation.'
eyebrow: 'Documentation'
heading: 'Where to go next.'
lede: 'The README stays focused on the product. Distribution flow and schemas live in dedicated documents.'
actions: 'Open README|https://github.com/theontho/gui-for-cli/blob/main/README.md|primary; Architecture|architecture.html'
footer_title: 'Documentation map'
footer_text: 'Product docs stay short; detailed engineering notes stay close to the code.'
---

::: section
::: wrap
::: grid two
::: card
{{ kicker: Product }}
### README
The top-level README describes the app, setup, common commands, bundles, config, and distribution packaging.

{{ link: Open README|https://github.com/theontho/gui-for-cli/blob/main/README.md|inline-link }}
:::

::: card
{{ kicker: Schemas }}
### Bundle schemas
`manifest.json` and page files are described by JSON Schemas in `docs/schema/`.

{{ link: Open schemas|https://github.com/theontho/gui-for-cli/tree/main/docs/schema|inline-link }}
:::

::: card
{{ kicker: Archive }}
### Earlier experiments
The SwiftUI app, Swift CLI, prototype renderers, and benchmark reports live on the `old-experimental` branch.

{{ link: Open the archive branch|https://github.com/theontho/gui-for-cli/tree/old-experimental|inline-link }}
:::

::: card
{{ kicker: Distribution }}
### Packaging
Signing, notarization, Tauri packages for each OS, release artifacts, self-updates, and embedded bundle defaults.

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
make site
open site/index.html
```

The generated HTML is written to `site/` and can be served by GitHub Pages.
:::
:::
