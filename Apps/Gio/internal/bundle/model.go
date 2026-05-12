package bundle

import (
	"encoding/json"
	"fmt"
	"strconv"
)

type AppBundle struct {
	Manifest            Manifest
	BundleRoot          string
	BundleWorkspaceRoot string
	BuiltinStringsRoot  string
	Strings             map[string]string
	LocalizationCode    string
	LocalizationOptions []LocalizationOption
}

type Manifest struct {
	ID                      string              `json:"id"`
	DisplayName             string              `json:"displayName"`
	Summary                 string              `json:"summary"`
	IconName                string              `json:"iconName"`
	IconEmoji               string              `json:"iconEmoji"`
	IconPath                string              `json:"iconPath"`
	DefaultLocalizationCode string              `json:"defaultLocalizationCode"`
	TerminalTextDirection   string              `json:"terminalTextDirection"`
	Pages                   []Page              `json:"pages"`
	Setup                   SetupSpec           `json:"setup"`
	ExitCodeReference       []ExitCodeReference `json:"exitCodeReference"`
	PageFiles               []string            `json:"-"`
}

type LocalizationOption struct {
	Code        string `json:"code"`
	DisplayName string `json:"displayName"`
}

type SetupSpec struct {
	Steps []SetupStep `json:"steps"`
}

type SetupStep struct {
	ID               string            `json:"id"`
	Kind             string            `json:"kind"`
	Label            string            `json:"label"`
	Value            string            `json:"value"`
	Optional         bool              `json:"optional"`
	Args             []string          `json:"arguments"`
	Env              map[string]string `json:"environment"`
	WorkingDirectory string            `json:"workingDirectory"`
}

type ExitCodeReference struct {
	Code     int    `json:"code"`
	Title    string `json:"title"`
	Summary  string `json:"summary"`
	Severity string `json:"severity"`
}

type Page struct {
	ID           string    `json:"id"`
	Title        string    `json:"title"`
	Summary      string    `json:"summary"`
	IconName     string    `json:"iconName"`
	IconEmoji    string    `json:"iconEmoji"`
	SidebarGroup string    `json:"sidebarGroup"`
	Sections     []Section `json:"sections"`
}

type Section struct {
	ID         string            `json:"id"`
	Title      string            `json:"title"`
	Subtitle   string            `json:"subtitle"`
	IconName   string            `json:"iconName"`
	IconEmoji  string            `json:"iconEmoji"`
	DataSource *ScriptDataSource `json:"dataSource"`
	Controls   []Control         `json:"controls"`
	Actions    []Action          `json:"actions"`
}

type Control struct {
	ID          string            `json:"id"`
	Label       string            `json:"label"`
	Kind        string            `json:"kind"`
	Value       string            `json:"value"`
	Placeholder string            `json:"placeholder"`
	Tooltip     string            `json:"tooltip"`
	PathType    string            `json:"pathType"`
	PathKind    string            `json:"pathKind"`
	PathMode    string            `json:"pathMode"`
	Options     []Option          `json:"options"`
	Columns     []ListColumn      `json:"columns"`
	Rows        []ListRow         `json:"rows"`
	RowTemplate *ListRow          `json:"rowTemplate"`
	Items       []ListItem        `json:"items"`
	RowActions  []Action          `json:"rowActions"`
	DataSource  *ScriptDataSource `json:"dataSource"`
	Settings    []ConfigSetting   `json:"settings"`
	ConfigFile  *ConfigFile       `json:"configFile"`
}

type ConfigSetting struct {
	ID          string            `json:"id"`
	Kind        string            `json:"kind"`
	Key         string            `json:"key"`
	Value       string            `json:"value"`
	Label       string            `json:"label"`
	Placeholder string            `json:"placeholder"`
	Tooltip     string            `json:"tooltip"`
	PathType    string            `json:"pathType"`
	PathKind    string            `json:"pathKind"`
	PathMode    string            `json:"pathMode"`
	Options     []Option          `json:"options"`
	DataSource  *ScriptDataSource `json:"dataSource"`
}

type ConfigFile struct {
	Path      string           `json:"path"`
	Format    string           `json:"format"`
	Bootstrap *ConfigBootstrap `json:"bootstrap"`
}

type ConfigBootstrap struct {
	Mode   string                 `json:"mode"`
	Script *ConfigBootstrapScript `json:"script"`
}

type ConfigBootstrapScript struct {
	Path             string            `json:"path"`
	Args             []string          `json:"arguments"`
	Env              map[string]string `json:"environment"`
	WorkingDirectory string            `json:"workingDirectory"`
}

type Option struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Selected bool   `json:"selected"`
	Status   string `json:"status"`
	Group    string `json:"group"`
}

type ListColumn struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type ListRow struct {
	ID      string            `json:"id"`
	Title   string            `json:"title"`
	Values  map[string]string `json:"values"`
	Status  string            `json:"status"`
	Tags    []Tag             `json:"tags"`
	Tooltip string            `json:"tooltip"`
}

type ListItem struct {
	Values map[string]string `json:"values"`
}

func (i *ListItem) UnmarshalJSON(data []byte) error {
	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	values := map[string]string{}
	for key, value := range raw {
		if key == "values" {
			nested, ok := value.(map[string]any)
			if !ok {
				return fmt.Errorf("list item values must be an object")
			}
			for nestedKey, nestedValue := range nested {
				values[nestedKey] = stringifyJSONValue(nestedValue)
			}
			continue
		}
		values[key] = stringifyJSONValue(value)
	}
	i.Values = values
	return nil
}

type Tag struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Style string `json:"style"`
}

func (t *Tag) UnmarshalJSON(data []byte) error {
	var title string
	if err := json.Unmarshal(data, &title); err == nil {
		t.ID = title
		t.Title = title
		t.Style = "secondary"
		return nil
	}
	type tagAlias Tag
	var decoded tagAlias
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	if decoded.ID == "" {
		decoded.ID = decoded.Title
	}
	if decoded.Style == "" {
		decoded.Style = "secondary"
	}
	*t = Tag(decoded)
	return nil
}

type ScriptDataSource struct {
	Path             string            `json:"path"`
	Args             []string          `json:"arguments"`
	Env              map[string]string `json:"environment"`
	WorkingDirectory string            `json:"workingDirectory"`
}

type Action struct {
	ID              string              `json:"id"`
	Title           string              `json:"title"`
	Role            string              `json:"role"`
	Tooltip         string              `json:"tooltip"`
	IconName        string              `json:"iconName"`
	IconEmoji       string              `json:"iconEmoji"`
	IconOnly        bool                `json:"iconOnly"`
	DisabledTooltip string              `json:"disabledTooltip"`
	Precheck        *ActionPrecheck     `json:"precheck"`
	Confirm         *ActionConfirmation `json:"confirm"`
	Command         Command             `json:"command"`
	VisibleWhen     []ActionCondition   `json:"visibleWhen"`
	DisabledWhen    []ActionCondition   `json:"disabledWhen"`
}

type ActionCondition struct {
	Placeholder        string   `json:"placeholder"`
	Equals             string   `json:"equals"`
	NotEquals          string   `json:"notEquals"`
	In                 []string `json:"in"`
	NotIn              []string `json:"notIn"`
	Exists             *bool    `json:"exists"`
	LessThan           string   `json:"lessThan"`
	LessThanOrEqual    string   `json:"lessThanOrEqual"`
	GreaterThan        string   `json:"greaterThan"`
	GreaterThanOrEqual string   `json:"greaterThanOrEqual"`
}

type ActionPrecheck struct {
	DiskSpaceGB    string `json:"diskSpaceGB"`
	DiskSpacePath  string `json:"diskSpacePath"`
	WarningMessage string `json:"warningMessage"`
}

type ActionConfirmation struct {
	Title              string `json:"title"`
	Message            string `json:"message"`
	ConfirmButtonTitle string `json:"confirmButtonTitle"`
	CancelButtonTitle  string `json:"cancelButtonTitle"`
	RequiredText       string `json:"requiredText"`
	Prompt             string `json:"prompt"`
}

type Command struct {
	Executable        string     `json:"executable"`
	Arguments         []string   `json:"arguments"`
	OptionalArguments [][]string `json:"optionalArguments"`
}

func stringifyJSONValue(value any) string {
	switch typed := value.(type) {
	case nil:
		return ""
	case string:
		return typed
	case bool:
		if typed {
			return "true"
		}
		return "false"
	case float64:
		return strconv.FormatFloat(typed, 'f', -1, 64)
	default:
		return fmt.Sprint(typed)
	}
}
