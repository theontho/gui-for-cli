live_design! {
    use link::theme::*;
    use link::shaders::*;
    use link::widgets::*;

    MakepadApp = {{MakepadApp}} {
        ui: <Root> {
            main_window = <Window> {
                body = <View> {
                    width: Fill, height: Fill, flow: Down, padding: 12, spacing: 8,
                    show_bg: true,
                    draw_bg: { color: #20242c }
                    header = <View> {
                        width: Fill, height: Fit, flow: Down, spacing: 4,
                        title = <Label> { text: "GUI for CLI Makepad", draw_text: { color: #fff, text_style: { font_size: 22 } } }
                        summary = <Label> { text: "", draw_text: { color: #cbd1dc } }
                    }
                    shell = <View> {
                        width: Fill, height: Fill, flow: Right, spacing: 8,
                        sidebar = <ScrollYView> {
                            width: 280, height: Fill, flow: Down, padding: 10, spacing: 6,
                            show_bg: true, draw_bg: { color: #2b303a }
                            setup_text = <Label> { text: "", draw_text: { color: #d9dee8 } }
                            setup_0 = <Button> { text: "" }
                            setup_1 = <Button> { text: "" }
                            setup_2 = <Button> { text: "" }
                            setup_3 = <Button> { text: "" }
                            setup_4 = <Button> { text: "" }
                            setup_5 = <Button> { text: "" }
                            setup_6 = <Button> { text: "" }
                            setup_7 = <Button> { text: "" }
                            setup_hint_0 = <Label> { text: "" }
                            setup_hint_1 = <Label> { text: "" }
                            setup_hint_2 = <Label> { text: "" }
                            setup_hint_3 = <Label> { text: "" }
                            setup_hint_4 = <Label> { text: "" }
                            setup_hint_5 = <Label> { text: "" }
                            setup_hint_6 = <Label> { text: "" }
                            setup_hint_7 = <Label> { text: "" }
                            pages_title = <Label> { text: "Pages", draw_text: { color: #fff, text_style: { font_size: 15 } } }
                            page_0 = <Button> { text: "" }
                            page_1 = <Button> { text: "" }
                            page_2 = <Button> { text: "" }
                            page_3 = <Button> { text: "" }
                            page_4 = <Button> { text: "" }
                            page_5 = <Button> { text: "" }
                            page_6 = <Button> { text: "" }
                            page_7 = <Button> { text: "" }
                            page_8 = <Button> { text: "" }
                            page_9 = <Button> { text: "" }
                            page_10 = <Button> { text: "" }
                            page_11 = <Button> { text: "" }
                            page_12 = <Button> { text: "" }
                            page_13 = <Button> { text: "" }
                            page_14 = <Button> { text: "" }
                            page_15 = <Button> { text: "" }
                            open_workspace = <Button> { text: "Open Workspace" }
                            toggle_terminal = <Button> { text: "Hide Terminal" }
                        }
                        main_area = <View> {
                            width: Fill, height: Fill, flow: Down, spacing: 8,
                            content = <ScrollYView> {
                                width: Fill, height: Fill, flow: Down, padding: 10, spacing: 8,
                                show_bg: true, draw_bg: { color: #f4f6fa }
                                page_title = <Label> { text: "", draw_text: { color: #151922, text_style: { font_size: 20 } } }
                                page_summary = <Label> { text: "", draw_text: { color: #3f4652 } }
                                page_body = <Markdown> { width: Fill, height: Fit }
                                controls_title = <Label> { text: "Controls", draw_text: { color: #151922, text_style: { font_size: 16 } } }
                            control_row_0 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_0 = <Label> { text: "" }
                                control_input_0 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_0 = <Button> { text: "Choose…" }
                                control_help_0 = <Label> { text: "" }
                            }
                            control_row_1 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_1 = <Label> { text: "" }
                                control_input_1 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_1 = <Button> { text: "Choose…" }
                                control_help_1 = <Label> { text: "" }
                            }
                            control_row_2 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_2 = <Label> { text: "" }
                                control_input_2 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_2 = <Button> { text: "Choose…" }
                                control_help_2 = <Label> { text: "" }
                            }
                            control_row_3 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_3 = <Label> { text: "" }
                                control_input_3 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_3 = <Button> { text: "Choose…" }
                                control_help_3 = <Label> { text: "" }
                            }
                            control_row_4 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_4 = <Label> { text: "" }
                                control_input_4 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_4 = <Button> { text: "Choose…" }
                                control_help_4 = <Label> { text: "" }
                            }
                            control_row_5 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_5 = <Label> { text: "" }
                                control_input_5 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_5 = <Button> { text: "Choose…" }
                                control_help_5 = <Label> { text: "" }
                            }
                            control_row_6 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_6 = <Label> { text: "" }
                                control_input_6 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_6 = <Button> { text: "Choose…" }
                                control_help_6 = <Label> { text: "" }
                            }
                            control_row_7 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_7 = <Label> { text: "" }
                                control_input_7 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_7 = <Button> { text: "Choose…" }
                                control_help_7 = <Label> { text: "" }
                            }
                            control_row_8 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_8 = <Label> { text: "" }
                                control_input_8 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_8 = <Button> { text: "Choose…" }
                                control_help_8 = <Label> { text: "" }
                            }
                            control_row_9 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_9 = <Label> { text: "" }
                                control_input_9 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_9 = <Button> { text: "Choose…" }
                                control_help_9 = <Label> { text: "" }
                            }
                            control_row_10 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_10 = <Label> { text: "" }
                                control_input_10 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_10 = <Button> { text: "Choose…" }
                                control_help_10 = <Label> { text: "" }
                            }
                            control_row_11 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_11 = <Label> { text: "" }
                                control_input_11 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_11 = <Button> { text: "Choose…" }
                                control_help_11 = <Label> { text: "" }
                            }
                            control_row_12 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_12 = <Label> { text: "" }
                                control_input_12 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_12 = <Button> { text: "Choose…" }
                                control_help_12 = <Label> { text: "" }
                            }
                            control_row_13 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_13 = <Label> { text: "" }
                                control_input_13 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_13 = <Button> { text: "Choose…" }
                                control_help_13 = <Label> { text: "" }
                            }
                            control_row_14 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_14 = <Label> { text: "" }
                                control_input_14 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_14 = <Button> { text: "Choose…" }
                                control_help_14 = <Label> { text: "" }
                            }
                            control_row_15 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_15 = <Label> { text: "" }
                                control_input_15 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_15 = <Button> { text: "Choose…" }
                                control_help_15 = <Label> { text: "" }
                            }
                            control_row_16 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_16 = <Label> { text: "" }
                                control_input_16 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_16 = <Button> { text: "Choose…" }
                                control_help_16 = <Label> { text: "" }
                            }
                            control_row_17 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_17 = <Label> { text: "" }
                                control_input_17 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_17 = <Button> { text: "Choose…" }
                                control_help_17 = <Label> { text: "" }
                            }
                            control_row_18 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_18 = <Label> { text: "" }
                                control_input_18 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_18 = <Button> { text: "Choose…" }
                                control_help_18 = <Label> { text: "" }
                            }
                            control_row_19 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_19 = <Label> { text: "" }
                                control_input_19 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_19 = <Button> { text: "Choose…" }
                                control_help_19 = <Label> { text: "" }
                            }
                            control_row_20 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_20 = <Label> { text: "" }
                                control_input_20 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_20 = <Button> { text: "Choose…" }
                                control_help_20 = <Label> { text: "" }
                            }
                            control_row_21 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_21 = <Label> { text: "" }
                                control_input_21 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_21 = <Button> { text: "Choose…" }
                                control_help_21 = <Label> { text: "" }
                            }
                            control_row_22 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_22 = <Label> { text: "" }
                                control_input_22 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_22 = <Button> { text: "Choose…" }
                                control_help_22 = <Label> { text: "" }
                            }
                            control_row_23 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                control_label_23 = <Label> { text: "" }
                                control_input_23 = <TextInput> { width: Fill, height: 34, empty_text: "" }
                                control_pick_23 = <Button> { text: "Choose…" }
                                control_help_23 = <Label> { text: "" }
                            }
                                actions_title = <Label> { text: "Actions", draw_text: { color: #151922, text_style: { font_size: 16 } } }
                            action_row_0 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_0 = <Button> { text: "" }
                                action_help_0 = <Label> { text: "" }
                            }
                            action_row_1 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_1 = <Button> { text: "" }
                                action_help_1 = <Label> { text: "" }
                            }
                            action_row_2 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_2 = <Button> { text: "" }
                                action_help_2 = <Label> { text: "" }
                            }
                            action_row_3 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_3 = <Button> { text: "" }
                                action_help_3 = <Label> { text: "" }
                            }
                            action_row_4 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_4 = <Button> { text: "" }
                                action_help_4 = <Label> { text: "" }
                            }
                            action_row_5 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_5 = <Button> { text: "" }
                                action_help_5 = <Label> { text: "" }
                            }
                            action_row_6 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_6 = <Button> { text: "" }
                                action_help_6 = <Label> { text: "" }
                            }
                            action_row_7 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_7 = <Button> { text: "" }
                                action_help_7 = <Label> { text: "" }
                            }
                            action_row_8 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_8 = <Button> { text: "" }
                                action_help_8 = <Label> { text: "" }
                            }
                            action_row_9 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_9 = <Button> { text: "" }
                                action_help_9 = <Label> { text: "" }
                            }
                            action_row_10 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_10 = <Button> { text: "" }
                                action_help_10 = <Label> { text: "" }
                            }
                            action_row_11 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_11 = <Button> { text: "" }
                                action_help_11 = <Label> { text: "" }
                            }
                            action_row_12 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_12 = <Button> { text: "" }
                                action_help_12 = <Label> { text: "" }
                            }
                            action_row_13 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_13 = <Button> { text: "" }
                                action_help_13 = <Label> { text: "" }
                            }
                            action_row_14 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_14 = <Button> { text: "" }
                                action_help_14 = <Label> { text: "" }
                            }
                            action_row_15 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_15 = <Button> { text: "" }
                                action_help_15 = <Label> { text: "" }
                            }
                            action_row_16 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_16 = <Button> { text: "" }
                                action_help_16 = <Label> { text: "" }
                            }
                            action_row_17 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_17 = <Button> { text: "" }
                                action_help_17 = <Label> { text: "" }
                            }
                            action_row_18 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_18 = <Button> { text: "" }
                                action_help_18 = <Label> { text: "" }
                            }
                            action_row_19 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_19 = <Button> { text: "" }
                                action_help_19 = <Label> { text: "" }
                            }
                            action_row_20 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_20 = <Button> { text: "" }
                                action_help_20 = <Label> { text: "" }
                            }
                            action_row_21 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_21 = <Button> { text: "" }
                                action_help_21 = <Label> { text: "" }
                            }
                            action_row_22 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_22 = <Button> { text: "" }
                                action_help_22 = <Label> { text: "" }
                            }
                            action_row_23 = <View> {
                                flow: Down, width: Fill, height: Fit, spacing: 3,
                                action_23 = <Button> { text: "" }
                                action_help_23 = <Label> { text: "" }
                            }
                            }
                            terminal = <View> {
                                width: Fill, height: 240, flow: Down, padding: 8, spacing: 5,
                                show_bg: true, draw_bg: { color: #151922 }
                                terminal_tabs = <View> {
                                    width: Fill, height: Fit, flow: Right, spacing: 5,
                            tab_0 = <Button> { text: "" }
                            tab_1 = <Button> { text: "" }
                            tab_2 = <Button> { text: "" }
                            tab_3 = <Button> { text: "" }
                            tab_4 = <Button> { text: "" }
                            tab_5 = <Button> { text: "" }
                            tab_6 = <Button> { text: "" }
                            tab_7 = <Button> { text: "" }
                            tab_8 = <Button> { text: "" }
                            tab_9 = <Button> { text: "" }
                            tab_10 = <Button> { text: "" }
                            tab_11 = <Button> { text: "" }
                                }
                                terminal_hint = <Label> { text: "", draw_text: { color: #b6becd } }
                                terminal_output = <TextInput> { width: Fill, height: Fill, is_read_only: true, text: "Ready." }
                            }
                        }
                    }
                }
            }
        }
    }
}
