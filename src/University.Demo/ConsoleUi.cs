namespace University.Demo;

/// <summary>Minimal console helpers: headings, notes and plain-text tables.</summary>
internal static class ConsoleUi
{
    public static bool PauseBetweenSteps { get; set; }

    private static int _step;

    public static void Step(string title)
    {
        if (_step > 0 && PauseBetweenSteps)
        {
            Write("\n  [Enter] next step", ConsoleColor.DarkGray);
            Console.ReadLine();
        }
        _step++;
        Console.WriteLine();
        Write($"══ {_step}. {title} ", ConsoleColor.Cyan);
        Write(new string('═', Math.Max(0, 90 - title.Length)) + "\n", ConsoleColor.Cyan);
    }

    public static void Info(string text) => Write($"  {text}\n", ConsoleColor.Gray);
    public static void Ok(string text) => Write($"  ✔ {text}\n", ConsoleColor.Green);
    public static void Fail(string text) => Write($"  ✘ {text}\n", ConsoleColor.Red);
    public static void Code(string text) => Write($"    {text}\n", ConsoleColor.DarkYellow);

    public static void Pending(IReadOnlyList<string> pending)
    {
        Write($"  Queued in the unit of work ({pending.Count}):\n", ConsoleColor.Gray);
        foreach (var p in pending)
            Code("• " + p);
    }

    public static void Table<T>(IEnumerable<T> rows, params (string Header, Func<T, object?> Value)[] columns)
    {
        var data = rows.Select(r => columns.Select(c => Format(c.Value(r))).ToArray()).ToList();
        if (data.Count == 0)
        {
            Info("(no rows)");
            return;
        }

        var widths = columns.Select((c, i) => Math.Max(c.Header.Length, data.Max(r => r[i].Length))).ToArray();
        Write("  " + string.Join(" │ ", columns.Select((c, i) => c.Header.PadRight(widths[i]))) + "\n", ConsoleColor.White);
        Write("  " + string.Join("─┼─", widths.Select(w => new string('─', w))) + "\n", ConsoleColor.DarkGray);
        foreach (var row in data)
            Console.WriteLine("  " + string.Join(" │ ", row.Select((v, i) => v.PadRight(widths[i]))));
    }

    private static string Format(object? value) => value switch
    {
        null => "—",
        DateTime dt => dt.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss"),   // timestamptz arrives as UTC
        decimal d => d.ToString("0.##"),
        _ => value.ToString() ?? "",
    };

    private static void Write(string text, ConsoleColor color)
    {
        var old = Console.ForegroundColor;
        Console.ForegroundColor = color;
        Console.Write(text);
        Console.ForegroundColor = old;
    }
}
