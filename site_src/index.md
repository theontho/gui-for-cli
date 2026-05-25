---
output: 'index.html'
title: 'GUI for CLI | Desktop apps for CLI bundles'
description: 'GUI for CLI turns portable CLI bundles into swiftui-macos and tauri-webui desktop apps.'
eyebrow: 'CLI tools, desktop UX'
heading: 'Turn a CLI bundle into a real desktop app.'
lede: 'GUI for CLI renders portable CLI-tool bundles as installable desktop applications. The two product frontends are swiftui-macos and tauri-webui, with WGSExtract as the first real app driving the design.'
actions: 'Explore frontends|frontends.html|primary; See experiments|experiments.html; WGSExtract story|wgsextract.html'
footer_title: 'GUI for CLI'
footer_text: 'A generic app shell for practical CLI workflows.'
auto_hero: false
---

::: raw
<header class="hero">
  <div class="wrap hero-grid">
    <div>
      <p class="eyebrow"><span class="pulse" aria-hidden="true"></span> CLI tools, desktop UX</p>
      <h1>Turn a CLI bundle into a real desktop app.</h1>
      <p class="lede">GUI for CLI renders portable CLI-tool bundles as installable desktop applications. The production frontends are <code>swiftui-macos</code> and <code>tauri-webui</code>; WGSExtract is the first real app that forced the model to handle real setup, data, commands, and packaging.</p>
      <div class="actions">
        <a class="btn primary" href="frontends.html">Explore frontends</a>
        <a class="btn" href="experiments.html">See experiments</a>
        <a class="btn" href="wgsextract.html">WGSExtract story</a>
      </div>
    </div>
    <aside class="hero-card" aria-label="Bundle flow">
      <div class="terminal">
        <div class="terminal-top" aria-hidden="true"><span></span><span></span><span></span></div>
        <pre><code># Inspect the first real app bundle
$ swift run --package-path platform/apple gui-for-cli bundle inspect examples/WGSExtract

# Run a production frontend
$ make run PLATFORM=swiftui-macos BUNDLE=examples/WGSExtract
$ make run PLATFORM=tauri BUNDLE=examples/WGSExtract</code></pre>
      </div>
      <div class="stats">
        <div><strong>2</strong><span>product frontends</span></div>
        <div><strong>29</strong><span>research surfaces</span></div>
        <div><strong>1st</strong><span>real app: WGSExtract</span></div>
      </div>
    </aside>
  </div>
</header>
:::

::: section
::: wrap
::: section-head
## What it does

GUI for CLI separates reusable bundle behavior from the UI shell. A bundle declares pages, controls, setup, commands, data sources, strings, icons, and state; each frontend renders that same model with platform-native expectations.
:::

::: grid three
::: card
{{ kicker: Bundle driven }}
### Portable app definitions
Bundles live in folders or archives with `manifest.json`, page schemas, scripts, strings, and resources. They can be inspected, validated, set up, and packaged.
:::

::: card
{{ kicker: Two product frontends }}
### `swiftui-macos` and `tauri-webui`
`swiftui-macos` is the native Apple app. `tauri-webui` packages the browser-based UI as a self-contained desktop app.
:::

::: card
{{ kicker: Research preserved }}
### Experiments moved out of the README
Renderer experiments are documented separately with their benchmark lessons, so the README stays focused on the product.
:::
:::
:::
:::

::: section
::: wrap
## Why WGSExtract mattered

WGSExtract is not a toy bundle. It has setup scripts, long-running genomics commands, file pickers, dynamic data rows, localized labels, terminal output, and release packaging. That pressure shaped the generic bundle runtime and proved which frontend surfaces were worth keeping as product paths.

{{ button: Read the WGSExtract story|wgsextract.html|primary }}
:::
:::
