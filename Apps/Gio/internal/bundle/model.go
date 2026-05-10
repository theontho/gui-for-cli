package bundle

type AppBundle struct {
	Manifest            Manifest
	BundleRoot          string
	BundleWorkspaceRoot string
	BuiltinStringsRoot  string
}

type Manifest struct {
	ID                      string              `json:"id"`
	DisplayName             string              `json:"displayName"`
	Summary                 string              `json:"summary"`
	DefaultLocalizationCode string              `json:"defaultLocalizationCode"`
	Pages                   []Page              `json:"pages"`
	Setup                   SetupSpec           `json:"setup"`
	ExitCodeReference       []ExitCodeReference `json:"exitCodeReference"`
	PageFiles               []string            `json:"-"`
}

type SetupSpec struct {
	Steps []SetupStep `json:"steps"`
}

type SetupStep struct {
	ID       string   `json:"id"`
	Kind     string   `json:"kind"`
	Label    string   `json:"label"`
	Value    string   `json:"value"`
	Optional bool     `json:"optional"`
	Args     []string `json:"arguments"`
}

type ExitCodeReference struct {
	Code    int    `json:"code"`
	Title   string `json:"title"`
	Summary string `json:"summary"`
}

type Page struct {
	ID           string    `json:"id"`
	Title        string    `json:"title"`
	Summary      string    `json:"summary"`
	IconName     string    `json:"iconName"`
	SidebarGroup string    `json:"sidebarGroup"`
	Sections     []Section `json:"sections"`
}

type Section struct {
	ID       string    `json:"id"`
	Title    string    `json:"title"`
	Subtitle string    `json:"subtitle"`
	Controls []Control `json:"controls"`
	Actions  []Action  `json:"actions"`
}

type Control struct {
	ID          string          `json:"id"`
	Label       string          `json:"label"`
	Kind        string          `json:"kind"`
	Value       string          `json:"value"`
	Placeholder string          `json:"placeholder"`
	Tooltip     string          `json:"tooltip"`
	Options     []Option        `json:"options"`
	Settings    []ConfigSetting `json:"settings"`
	ConfigFile  *ConfigFile     `json:"configFile"`
}

type ConfigSetting struct {
	ID          string   `json:"id"`
	Kind        string   `json:"kind"`
	Key         string   `json:"key"`
	Value       string   `json:"value"`
	Label       string   `json:"label"`
	Placeholder string   `json:"placeholder"`
	Tooltip     string   `json:"tooltip"`
	Options     []Option `json:"options"`
}

type ConfigFile struct {
	Path string `json:"path"`
}

type Option struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Selected bool   `json:"selected"`
}

type Action struct {
	ID              string            `json:"id"`
	Title           string            `json:"title"`
	Tooltip         string            `json:"tooltip"`
	DisabledTooltip string            `json:"disabledTooltip"`
	Command         Command           `json:"command"`
	VisibleWhen     []ActionCondition `json:"visibleWhen"`
	DisabledWhen    []ActionCondition `json:"disabledWhen"`
}

type ActionCondition struct {
	Placeholder string `json:"placeholder"`
}

type Command struct {
	Executable        string     `json:"executable"`
	Arguments         []string   `json:"arguments"`
	OptionalArguments [][]string `json:"optionalArguments"`
}
