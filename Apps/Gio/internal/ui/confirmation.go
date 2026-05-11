package ui

import (
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget/material"
)

func (g *GioApp) layoutPendingConfirmation(gtx layout.Context) layout.Dimensions {
	pending := g.pendingConfirm
	if pending == nil || pending.action.Confirm == nil {
		return layout.Dimensions{}
	}
	confirmation := pending.action.Confirm
	for g.cancelButton.Clicked(gtx) {
		g.pendingConfirm = nil
		g.window.Invalidate()
	}
	for g.confirmButton.Clicked(gtx) {
		required := strings.TrimSpace(interpolate(confirmation.RequiredText, g.contextValues(pending.rowValues)))
		if required != "" && g.confirmInput.Text() != required {
			g.appendLog(g.stringLabel("app.confirmation.mismatchLog", "Confirmation text does not match."))
			continue
		}
		action := pending.action
		actionKey := pending.actionKey
		rowValues := cloneMap(pending.rowValues)
		g.pendingConfirm = nil
		g.runAction(action, rowValues, actionKey)
	}
	return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		children := []layout.FlexChild{
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return material.H6(g.theme, confirmation.Title).Layout(gtx)
			}),
		}
		if confirmation.Message != "" {
			children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return material.Body1(g.theme, interpolate(confirmation.Message, g.contextValues(pending.rowValues))).Layout(gtx)
			}))
		}
		if strings.TrimSpace(confirmation.RequiredText) != "" {
			prompt := confirmation.Prompt
			if prompt == "" {
				prompt = g.stringLabel("app.confirmation.defaultPrompt", "Type the required text to confirm.")
			}
			children = append(children,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return mutedText(g.theme, interpolate(prompt, g.contextValues(pending.rowValues))).Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return material.Editor(g.theme, &g.confirmInput, interpolate(confirmation.RequiredText, g.contextValues(pending.rowValues))).Layout(gtx)
				}),
			)
		}
		cancelTitle := confirmation.CancelButtonTitle
		if cancelTitle == "" {
			cancelTitle = g.stringLabel("app.confirmation.cancelButton.title", "Cancel")
		}
		confirmTitle := confirmation.ConfirmButtonTitle
		if confirmTitle == "" {
			confirmTitle = pending.action.Title
		}
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Horizontal}.Layout(
				gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return material.Button(g.theme, &g.cancelButton, cancelTitle).Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Spacer{Width: unit.Dp(8)}.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return material.Button(g.theme, &g.confirmButton, confirmTitle).Layout(gtx)
				}),
			)
		}))
		children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Spacer{Height: unit.Dp(20)}.Layout(gtx)
		}))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
	})
}
