
public static class LocalJournalInspector
{
    public static void InspectBxml(string input, string output) {
        var state = BxmlState.Parse(File.ReadAllBytes(input));
        File.WriteAllText(output, JsonSerializer.Serialize(StateNode(state.Root, state.Strings), new JsonSerializerOptions { WriteIndented = true }));
    }
    public static void InspectCollectionAssets(string zipPath, string output) {
        using var zip = System.IO.Compression.ZipFile.OpenRead(zipPath);
        byte[] ReadEntry(System.IO.Compression.ZipArchiveEntry entry) {
            using var input = entry.Open(); using var buffer = new MemoryStream(); input.CopyTo(buffer); return buffer.ToArray();
        }
        var manifest = BxmlState.Parse(ReadEntry(zip.GetEntry("source/manifest.xml")!));
        var catalog = new List<object>(); Directory.CreateDirectory(output);
        foreach (var item in manifest.Walk()) {
            var node = item.Node;
            string? Property(string id) => node.Children.FirstOrDefault(c => c.Attributes.Any(a => manifest.Strings[a.KeyIndex] == "id" && manifest.Strings[a.ValueIndex] == id))?.Attributes
                .Where(a => manifest.Strings[a.KeyIndex] == "value").Select(a => manifest.Strings[a.ValueIndex]).FirstOrDefault();
            var type = Property("TypeId"); var file = Property("FileName");
            if (type == null || file == null || !(type.StartsWith("Collection") || type == "CareerTrackChallenges" || type == "ChallengeDataSet" || type == "ProgressionThreadsMap")) continue;
            var entry = zip.GetEntry("source/" + file.Replace('\\', '/'));
            if (entry == null) continue;
            var state = BxmlState.Parse(ReadEntry(entry));
            var destination = Path.GetFileName(entry.FullName) + ".json";
            File.WriteAllText(Path.Combine(output, destination), JsonSerializer.Serialize(StateNode(state.Root, state.Strings), new JsonSerializerOptions { WriteIndented = true }));
            catalog.Add(new { Type = type, File = file, Output = destination });
        }
        File.WriteAllText(Path.Combine(output, "catalog.json"), JsonSerializer.Serialize(catalog, new JsonSerializerOptions { WriteIndented = true }));
    }
    static object StateNode(BxmlNode node, List<string> strings) => new {
        Name = strings[node.NameIndex],
        Attributes = node.Attributes.Select(a => new { Key = strings[a.KeyIndex], Value = strings[a.ValueIndex] }),
        Children = node.Children.Select(c => StateNode(c, strings))
    };
    public static void Inspect(string path, string output)
    {
        var document = Fh6ProfileEditorDocument.Load(path);
        var relevant = new System.Text.RegularExpressions.Regex(
            "rival|journal|accolade|challenge|progression|completion|festival|collection",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        var options = new JsonSerializerOptions { WriteIndented = true };
        var properties = document.Properties.Walk().Select(item => new {
            item.Path, Type = item.Property.TypeName, Value = item.Property.DisplayValue,
            item.Property.Offset, item.Property.ValueOffset
        }).ToArray();
        var records = document.Binary.Records.Select(record => new {
            record.Name, record.Serializer, record.Ordinal,
            Size = record.Payload.Length, record.PayloadOffset
        }).ToArray();
        var strings = document.Bxml.Strings.Where(s => relevant.IsMatch(s)).ToArray();
        var databaseStrings = document.ScanStrings(ProfileStringSource.Database, 6)
            .Where(s => relevant.IsMatch(s.Value)).ToArray();
        // Parse before creating output: reject encrypted/invalid inputs without artifacts.
        Directory.CreateDirectory(output);
        File.WriteAllText(Path.Combine(output, "properties.json"), JsonSerializer.Serialize(properties, options));
        File.WriteAllText(Path.Combine(output, "journal-candidates.json"), JsonSerializer.Serialize(new {
            Properties = properties.Where(p => relevant.IsMatch(p.Path)),
            Records = records.Where(r => relevant.IsMatch(r.Name + " " + r.Serializer)),
            StateStrings = strings, DatabaseStrings = databaseStrings
        }, options));
        File.WriteAllText(Path.Combine(output, "records.json"), JsonSerializer.Serialize(records, options));
        File.WriteAllBytes(Path.Combine(output, "profile.sqlite"), document.DatabaseBytes);
        File.WriteAllText(Path.Combine(output, "state-tree.json"), JsonSerializer.Serialize(StateNode(document.Bxml.Root, document.Bxml.Strings), options));
        foreach (var record in document.Binary.Records.Where(r => relevant.IsMatch(r.Name))) {
            File.WriteAllBytes(Path.Combine(output, "record-" + record.Ordinal + ".bin"), record.Payload);
        }
        File.WriteAllText(Path.Combine(output, "summary.json"), JsonSerializer.Serialize(new {
            document.WasCompressed, document.OriginalSize, document.InflatedSize,
            Properties = properties.Length, Records = records.Length,
            DatabaseBytes = document.DatabaseBytes.Length,
            SqliteIntegrity = "Not checked; export only"
        }, options));
    }
}