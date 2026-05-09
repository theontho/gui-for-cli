using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace GUIForCLIWindows.Core;

public static partial class RenderingEngine
{
    public static IReadOnlyList<ListRowSpec> HydrateRows(ControlSpec control)
    {
        if (control.Items.Count == 0)
        {
            return control.Rows;
        }

        var template = control.RowTemplate ?? new ListRowSpec
        {
            Id = "{{id}}",
            Title = "{{name}}",
            Values = control.Columns.ToDictionary(column => column.Id, column => $"{{{{{column.Id}}}}}"),
            Status = "{{status}}",
        };

        return control.Items.Select((item, index) =>
        {
            var values = item.ValuesOrItem();
            var fallbackID = NonEmpty(ValueOrNull(values, "id")) ?? $"row-{index + 1}";
            var id = NonEmpty(InterpolateItem(template.Id, values)) ?? fallbackID;
            return new ListRowSpec
            {
                Id = id,
                Title = NonEmpty(template.Title is null ? null : InterpolateItem(template.Title, values)),
                Values = template.Values.ToDictionary(pair => pair.Key, pair => InterpolateItem(pair.Value, values)),
                Status = NonEmpty(template.Status is null ? null : InterpolateItem(template.Status, values)),
                Tags = template.Tags
                    .Select(tag => tag with
                    {
                        Id = InterpolateItem(tag.Id, values),
                        Title = InterpolateItem(tag.Title, values),
                    })
                    .Where(tag => tag.Title.Trim().Length > 0)
                    .ToList(),
                Tooltip = NonEmpty(template.Tooltip is null ? null : InterpolateItem(template.Tooltip, values)),
            };
        }).ToList();
    }

    public static RenderContext RowContext(RenderContext baseContext, ListRowSpec row)
    {
        var rowValues = new Dictionary<string, string>(row.Values)
        {
            ["id"] = row.Id ?? "",
            ["title"] = row.Title ?? row.Id ?? "",
        };
        if (row.Status is not null)
        {
            rowValues["status"] = row.Status;
        }

        return baseContext with { RowValues = rowValues };
    }

    public static ControlSpec ApplyDataSourcePayload(ControlSpec control, DataSourcePayload payload) =>
        control.WithDataSourcePayload(payload);

    private static string InterpolateItem(string? value, IReadOnlyDictionary<string, string> values) =>
        PlaceholderPattern.Replace(value ?? "", match =>
        {
            var raw = match.Groups[1].Value.Trim();
            var placeholder = raw.StartsWith("item.", StringComparison.Ordinal) ? raw[5..] : raw;
            return ValueOrNull(values, placeholder) ?? "";
        });

    private static string? NonEmpty(string? value)
    {
        var text = value ?? "";
        return text.Length > 0 ? text : null;
    }

}
