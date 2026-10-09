using Npgsql;

namespace University.Data.Infrastructure;

internal static class ReaderExtensions
{
    /// <summary>Reads a column by name; DBNull becomes default(T) (null for nullable types).</summary>
    public static T Get<T>(this NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? default! : reader.GetFieldValue<T>(ordinal);
    }
}
