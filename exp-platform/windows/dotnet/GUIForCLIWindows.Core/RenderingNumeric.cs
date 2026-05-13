using System.Globalization;

namespace GUIForCLIWindows.Core;

public static partial class RenderingEngine
{
    public static double EvaluateNumeric(string? expression) => new NumericParser(expression ?? "").Parse();

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
