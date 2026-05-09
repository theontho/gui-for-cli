using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace GUIForCLIWindows.Core;

public static partial class RenderingEngine
{
    public static bool IsActionVisible(ActionSpec action, RenderContext context) =>
        action.VisibleWhen.All(condition => ConditionMatches(condition, context));

    public static string? DisabledReason(ActionSpec action, RenderContext context, string fallback = "This action is not available.")
    {
        return action.DisabledWhen.Any(condition => ConditionMatches(condition, context))
            ? action.DisabledTooltip is null ? fallback : Interpolate(action.DisabledTooltip, context)
            : null;
    }

    public static bool ConditionMatches(ActionConditionSpec condition, RenderContext context)
    {
        var value = (ContextValue(context, condition.Placeholder) ?? "").Trim();
        if (condition.Exists is not null && condition.Exists.Value != value.Length > 0)
        {
            return false;
        }

        if (condition.EqualTo is not null && value != Interpolate(condition.EqualTo, context))
        {
            return false;
        }

        if (condition.NotEquals is not null && value == Interpolate(condition.NotEquals, context))
        {
            return false;
        }

        if (condition.In.Count > 0 && !condition.In.Select(item => Interpolate(item, context)).Contains(value))
        {
            return false;
        }

        if (condition.NotIn.Select(item => Interpolate(item, context)).Contains(value))
        {
            return false;
        }

        if (condition.LessThan is not null && !CompareNumeric(value, Interpolate(condition.LessThan, context), (left, right) => left < right))
        {
            return false;
        }

        if (condition.LessThanOrEqual is not null && !CompareNumeric(value, Interpolate(condition.LessThanOrEqual, context), (left, right) => left <= right))
        {
            return false;
        }

        if (condition.GreaterThan is not null && !CompareNumeric(value, Interpolate(condition.GreaterThan, context), (left, right) => left > right))
        {
            return false;
        }

        if (condition.GreaterThanOrEqual is not null && !CompareNumeric(value, Interpolate(condition.GreaterThanOrEqual, context), (left, right) => left >= right))
        {
            return false;
        }

        return true;
    }

    public static double EvaluateNumeric(string? expression) => new NumericParser(expression ?? "").Parse();

    private static bool CompareNumeric(string left, string right, Func<double, double, bool> op)
    {
        var leftValue = EvaluateNumeric(left);
        var rightValue = EvaluateNumeric(right);
        return double.IsFinite(leftValue) && double.IsFinite(rightValue) && op(leftValue, rightValue);
    }

    private sealed class NumericParser(string text)
    {
        private int _index;

        public double Parse()
        {
            var value = Expression();
            SkipWhitespace();
            return _index == text.Length ? value : double.NaN;
        }

        private double Expression()
        {
            var value = Term();
            while (true)
            {
                SkipWhitespace();
                if (Consume("+"))
                {
                    value += Term();
                }
                else if (Consume("-"))
                {
                    value -= Term();
                }
                else
                {
                    return value;
                }
            }
        }

        private double Term()
        {
            var value = Factor();
            while (true)
            {
                SkipWhitespace();
                if (Consume("*"))
                {
                    value *= Factor();
                }
                else if (Consume("/"))
                {
                    value /= Factor();
                }
                else
                {
                    return value;
                }
            }
        }

        private double Factor()
        {
            SkipWhitespace();
            if (Consume("+"))
            {
                return Factor();
            }

            if (Consume("-"))
            {
                return -Factor();
            }

            if (Consume("("))
            {
                var value = Expression();
                return Consume(")") ? value : double.NaN;
            }

            return Number();
        }

        private double Number()
        {
            SkipWhitespace();
            var start = _index;
            while (_index < text.Length && (char.IsAsciiDigit(text[_index]) || text[_index] == '.'))
            {
                _index += 1;
            }

            return start == _index
                ? double.NaN
                : double.Parse(text[start.._index], CultureInfo.InvariantCulture);
        }

        private bool Consume(string token)
        {
            if (_index < text.Length && text[_index].ToString() == token)
            {
                _index += 1;
                return true;
            }

            return false;
        }

        private void SkipWhitespace()
        {
            while (_index < text.Length && char.IsWhiteSpace(text[_index]))
            {
                _index += 1;
            }
        }
    }
}
