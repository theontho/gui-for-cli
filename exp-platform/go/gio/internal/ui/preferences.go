package ui

import (
	"fmt"
	"image/color"
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget/material"

	"github.com/theontho/gui-for-cli/apps/gio/internal/bundle"
)

func (g *GioApp) layoutStandardOptions(gtx layout.Context) layout.Dimensions {
	children := []layout.FlexChild{
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.H6(g.theme, g.stringLabel("app.standardOptions.title", "Standard Options")).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
		}),
	}
	if len(g.bundle.LocalizationOptions) > 1 {
		children = append(children,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return g.layoutPreferencePicker(
					gtx,
					"preference:locale",
					g.stringLabel("language.setting.label", "Language"),
					g.localizationPreferenceOptions(),
					g.selectedLocalizationCode(),
					func(value string) {
						if value == "" {
							g.state.LocalizationCode = nil
						} else {
							g.state.LocalizationCode = &value
						}
						g.saveState()
						if err := g.reloadLocalization(value); err != nil {
							g.appendLog(fmt.Sprintf("Could not change language: %v", err))
						}
					},
				)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
			}),
		)
	}
	children = append(children,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return g.layoutPreferencePicker(
				gtx,
				"preference:iconSet",
				g.stringLabel("app.iconSet.label", "Icons"),
				[]bundle.Option{
					{ID: "platform", Title: g.stringLabel("app.iconSet.bootstrapIcons", "Platform Icons")},
					{ID: "emoji", Title: g.stringLabel("app.iconSet.emoji", "Emoji")},
				},
				g.state.IconSet,
				func(value string) {
					g.state.IconSet = normalizeIconSet(value)
					g.saveState()
				},
			)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return g.layoutPreferencePicker(
				gtx,
				"preference:colorTheme",
				g.stringLabel("app.colorTheme.label", "Theme"),
				[]bundle.Option{
					{ID: "system", Title: g.stringLabel("app.colorTheme.system", "System")},
					{ID: "light", Title: g.stringLabel("app.colorTheme.light", "Light")},
					{ID: "dark", Title: g.stringLabel("app.colorTheme.dark", "Dark")},
				},
				g.state.ColorTheme,
				func(value string) {
					g.state.ColorTheme = normalizeColorTheme(value)
					g.applyTheme()
					g.saveState()
				},
			)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(8)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return g.layoutPreferencePicker(
				gtx,
				"preference:webUIFont",
				g.stringLabel("app.webUIFont.label", "Web Font"),
				[]bundle.Option{
					{ID: "system", Title: g.stringLabel("app.webUIFont.system", "System")},
					{ID: "sfPro", Title: g.stringLabel("app.webUIFont.sfPro", "SF Pro when available")},
				},
				g.state.WebUIFont,
				func(value string) {
					g.state.WebUIFont = normalizeWebUIFont(value)
					g.saveState()
				},
			)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(16)}.Layout(gtx)
		}),
	)
	return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	})
}

func (g *GioApp) layoutPreferencePicker(gtx layout.Context, id string, label string, options []bundle.Option, selected string, onSelect func(string)) layout.Dimensions {
	state := g.dropdownFor(id, options, selected)
	state.index = selectedOptionIndex(state.options, selected)
	for state.button.Clicked(gtx) {
		if len(state.options) == 0 {
			continue
		}
		state.index = (state.index + 1) % len(state.options)
		onSelect(state.options[state.index].ID)
	}
	value := selected
	if len(state.options) > 0 {
		value = displayOption(state.options[state.index])
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Body1(g.theme, label).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(4)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Button(g.theme, &state.button, value).Layout(gtx)
		}),
	)
}

func (g *GioApp) localizationPreferenceOptions() []bundle.Option {
	defaultName := g.bundle.LocalizationCode
	for _, option := range g.bundle.LocalizationOptions {
		if option.Code == g.bundle.Manifest.DefaultLocalizationCode {
			defaultName = option.DisplayName
			break
		}
	}
	options := []bundle.Option{{
		ID:    "",
		Title: fmt.Sprintf("%s - %s", g.stringLabel("language.setting.systemDefault", "Use system default"), defaultName),
	}}
	for _, option := range g.bundle.LocalizationOptions {
		options = append(options, bundle.Option{ID: option.Code, Title: option.DisplayName})
	}
	return options
}

func (g *GioApp) selectedLocalizationCode() string {
	if g.state.LocalizationCode == nil {
		return ""
	}
	return *g.state.LocalizationCode
}

func (g *GioApp) reloadLocalization(code string) error {
	loaded, err := bundle.Load(bundle.LoadOptions{
		BundleRoot:         g.bundle.BundleRoot,
		BuiltinStringsRoot: g.bundle.BuiltinStringsRoot,
		LocalizationCode:   code,
	})
	if err != nil {
		return err
	}
	g.bundle = loaded
	if !g.pageExists(g.activePageID) {
		g.activePageID = ""
		if len(g.bundle.Manifest.Pages) > 0 {
			g.activePageID = g.bundle.Manifest.Pages[0].ID
		}
		g.state.SelectedPageID = g.activePageID
	}
	g.ensureMainTerminal()
	g.appendLog(fmt.Sprintf("Language changed to %s", loaded.LocalizationCode))
	return nil
}

func (g *GioApp) normalizePreferences() {
	g.state.IconSet = normalizeIconSet(g.state.IconSet)
	g.state.ColorTheme = normalizeColorTheme(g.state.ColorTheme)
	g.state.WebUIFont = normalizeWebUIFont(g.state.WebUIFont)
}

func normalizeIconSet(value string) string {
	if value == "emoji" {
		return "emoji"
	}
	return "platform"
}

func normalizeColorTheme(value string) string {
	switch value {
	case "light", "dark":
		return value
	default:
		return "system"
	}
}

func normalizeWebUIFont(value string) string {
	if value == "sfPro" {
		return "sfPro"
	}
	return "system"
}

func (g *GioApp) applyTheme() {
	g.normalizePreferences()
	switch g.state.ColorTheme {
	case "dark":
		g.theme.Palette.Bg = color.NRGBA{R: 24, G: 24, B: 27, A: 255}
		g.theme.Palette.Fg = color.NRGBA{R: 244, G: 244, B: 245, A: 255}
		g.theme.Palette.ContrastBg = color.NRGBA{R: 63, G: 63, B: 70, A: 255}
		g.theme.Palette.ContrastFg = color.NRGBA{R: 244, G: 244, B: 245, A: 255}
	default:
		g.theme.Palette.Bg = color.NRGBA{R: 255, G: 255, B: 255, A: 255}
		g.theme.Palette.Fg = color.NRGBA{A: 255}
		g.theme.Palette.ContrastBg = color.NRGBA{R: 228, G: 228, B: 231, A: 255}
		g.theme.Palette.ContrastFg = color.NRGBA{R: 24, G: 24, B: 27, A: 255}
	}
}

func (g *GioApp) iconPrefix(textIcon string, iconName string, fallback string) string {
	if g.state.IconSet == "emoji" && strings.TrimSpace(textIcon) != "" {
		return textIcon + " "
	}
	if strings.TrimSpace(iconName) != "" && strings.TrimSpace(fallback) != "" {
		return fallback + " "
	}
	if strings.TrimSpace(textIcon) != "" {
		return textIcon + " "
	}
	return ""
}
