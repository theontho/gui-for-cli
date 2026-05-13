package ui

import (
	"fmt"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget/material"
)

func (g *GioApp) layoutDataSourceError(gtx layout.Context, key string, message string) layout.Dimensions {
	button := g.dataSourceRetryButtonFor(key)
	for button.Clicked(gtx) {
		delete(g.dataSourceErrors, key)
		if err := g.refreshDataSourcesForPage(g.activePageID); err != nil {
			g.appendLog(fmt.Sprintf("Data source retry failed: %v", err))
		}
	}
	return layout.Flex{Axis: layout.Vertical}.Layout(
		gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return warningText(g.theme, message).Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(4)}.Layout(gtx)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return material.Button(g.theme, button, g.stringLabel("app.retryButton.title", "Retry")).Layout(gtx)
		}),
	)
}
