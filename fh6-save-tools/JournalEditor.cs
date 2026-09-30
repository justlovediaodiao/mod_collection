// Uses the DVS-code FH6 profile parser distributed in vendor/.
public static class JournalEditor
{
    public static ulong Hash(string text) {
        unchecked { ulong h=14695981039346656037UL; foreach(byte b in System.Text.Encoding.UTF8.GetBytes(text)) h=(h^b)*1099511628211UL; return h; }
    }
    public static Dictionary<ulong,List<int>> Index(byte[] bytes) {
        var result=new Dictionary<ulong,List<int>>();
        for(int i=12;i+40<bytes.Length;i++) {
            ulong key=BitConverter.ToUInt64(bytes,i);
            if(key==0 || key!=BitConverter.ToUInt64(bytes,i+8)) continue;
            if(!result.TryGetValue(key,out var positions)) result[key]=positions=new List<int>();
            positions.Add(i);
        }
        return result;
    }
    public static int Find(byte[] bytes,ulong hash,int start,int end) {
        for(int i=start;i+8<end;i++) if(BitConverter.ToUInt64(bytes,i)==hash) return i;
        return -1;
    }
    static int Locate(byte[] bytes,string id) {
        ulong key=Hash(id); var positions=new List<int>();
        for(int i=12;i+75<=bytes.Length;i++) if(BitConverter.ToUInt64(bytes,i)==key && BitConverter.ToUInt64(bytes,i+8)==key) positions.Add(i);
        if(positions.Count!=1) throw new InvalidDataException("Record not unique: "+id);
        return positions[0];
    }
    static string? Attr(BxmlState state,BxmlNode node,string key) => node.Attributes.Where(a=>state.Strings[a.KeyIndex]==key).Select(a=>state.Strings[a.ValueIndex]).SingleOrDefault();
    static string Digest(byte[] bytes) => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes));
    public static void Edit(string input,string planPath,string output,string reportPath) {
        if(File.Exists(output) || File.Exists(reportPath)) throw new IOException("Choose new output paths");
        byte[] original=File.ReadAllBytes(input);
        using var plan=JsonDocument.Parse(File.ReadAllText(planPath)); var root=plan.RootElement;
        if(Digest(original)!=root.GetProperty("SourceSHA256").GetString()) throw new InvalidDataException("Plan source hash mismatch");
        var document=Fh6ProfileEditorDocument.Parse(original);
        if(!document.Serialize().AsSpan().SequenceEqual(original)) throw new InvalidDataException("Unedited roundtrip changed source");
        var record=document.Binary.Records.Single(r=>r.Name=="CollectionCampaignSaveState" && r.Serializer=="BaseChallengeSaveState");
        var bytes=record.Payload; var before=(byte[])bytes.Clone(); var allowed=new HashSet<int>(); var changed=new List<object>(); var ids=new HashSet<string>();
        var template=Convert.FromHexString("0101010000000100000000000000000100000000000000");
        long timestamp=DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()*1000;
        foreach(var row in root.GetProperty("Entries").EnumerateArray()) {
            string id=row.GetProperty("CollectionItemId").GetString()!;
            if(!ids.Add(id)) throw new InvalidDataException("Duplicate selection: "+id);
            int p=Locate(bytes,id); uint expected=row.GetProperty("ExpectedProgress").GetUInt32(); uint target=row.GetProperty("TargetProgress").GetUInt32();
            if(target==0 || target<=expected || row.GetProperty("EntryLength").GetInt32()!=75) throw new InvalidDataException("Unsupported target/layout: "+id);
            if(BitConverter.ToUInt64(bytes,p+16)!=Hash(row.GetProperty("ChallengeId").GetString()!) || BitConverter.ToUInt32(bytes,p+28)!=1 || BitConverter.ToUInt64(bytes,p+32)!=Hash(row.GetProperty("GoalId").GetString()!)) throw new InvalidDataException("Challenge/goal identity mismatch: "+id);
            if(bytes[p+40]!=0 || bytes[p+41]!=1 || BitConverter.ToUInt32(bytes,p+42)!=expected || bytes[p+46]!=1 || BitConverter.ToUInt64(bytes,p+47)!=BitConverter.ToUInt64(bytes,p+32) || BitConverter.ToUInt64(bytes,p+55)!=0 || BitConverter.ToUInt64(bytes,p+63)!=0) throw new InvalidDataException("Unsupported incomplete state: "+id);
            template.CopyTo(bytes,p+40); BitConverter.GetBytes(target).CopyTo(bytes,p+42); BitConverter.GetBytes(timestamp).CopyTo(bytes,p+63);
            for(int i=p+40;i<p+71;i++) allowed.Add(i);
            changed.Add(new {Id=id,Name=row.GetProperty("Name").GetString(),Offset=p,Before=expected,After=target});
        }
        if(changed.Count==0) throw new InvalidDataException("Empty plan");
        for(int i=0;i<bytes.Length;i++) if(bytes[i]!=before[i] && !allowed.Contains(i)) throw new InvalidDataException("Unexpected binary mutation");
        var state=document.Bxml; var currencyChanges=new List<object>(); var currencyKeys=new HashSet<string>();
        foreach(var total in root.GetProperty("CurrencyChanges").EnumerateArray()) {
            string key=total.GetProperty("Key").GetString()!;
            if(!currencyKeys.Add(key)) throw new InvalidDataException("Duplicate currency key");
            int old=total.GetProperty("Before").GetInt32(), next=total.GetProperty("After").GetInt32();
            if(next<=old) throw new InvalidDataException("Expected positive currency delta");
            var map=state.Walk().Select(w=>w.Node).Single(n=>state.Strings[n.NameIndex]=="map_element" && n.Children.Any(c=>state.Strings[c.NameIndex]=="key" && Attr(state,c,"value")==key));
            var value=map.Children.Single(n=>state.Strings[n.NameIndex]=="value");
            var property=value.Children.Single(n=>state.Strings[n.NameIndex]=="property" && Attr(state,n,"id")=="Total");
            var attribute=property.Attributes.Single(a=>state.Strings[a.KeyIndex]=="value");
            if(state.Strings[attribute.ValueIndex]!=old.ToString(System.Globalization.CultureInfo.InvariantCulture)) throw new InvalidDataException("Currency precondition failed: "+key);
            attribute.ValueIndex=state.Intern(next.ToString(System.Globalization.CultureInfo.InvariantCulture));
            currencyChanges.Add(new {Key=key,Before=old,After=next});
        }
        if(currencyChanges.Count==0) throw new InvalidDataException("Missing currency plan");
        byte[] edited=document.Serialize(); var parsed=Fh6ProfileEditorDocument.Parse(edited); var baseline=Fh6ProfileEditorDocument.Parse(original);
        if(!edited.AsSpan().SequenceEqual(parsed.Serialize())) throw new InvalidDataException("Edited roundtrip failed");
        if(!baseline.Sections[0].Payload.AsSpan().SequenceEqual(parsed.Sections[0].Payload) || !baseline.DatabaseBytes.AsSpan().SequenceEqual(parsed.DatabaseBytes)) throw new InvalidDataException("Unrelated section changed");
        for(int i=0;i<baseline.Binary.Records.Count;i++) if(i!=record.Ordinal && !baseline.Binary.Records[i].Payload.AsSpan().SequenceEqual(parsed.Binary.Records[i].Payload)) throw new InvalidDataException("Unrelated binary record changed");
        var oldNodes=baseline.Bxml.Walk().Select(w=>w.Node).ToArray(); var newNodes=parsed.Bxml.Walk().Select(w=>w.Node).ToArray();
        if(oldNodes.Length!=newNodes.Length) throw new InvalidDataException("State shape changed");
        int attributeChanges=0;
        for(int i=0;i<oldNodes.Length;i++) {
            var a=oldNodes[i]; var b=newNodes[i];
            if(baseline.Bxml.Strings[a.NameIndex]!=parsed.Bxml.Strings[b.NameIndex] || a.Attributes.Count!=b.Attributes.Count || a.Children.Count!=b.Children.Count) throw new InvalidDataException("State shape changed");
            for(int j=0;j<a.Attributes.Count;j++) {
                if(baseline.Bxml.Strings[a.Attributes[j].KeyIndex]!=parsed.Bxml.Strings[b.Attributes[j].KeyIndex]) throw new InvalidDataException("State key changed");
                if(baseline.Bxml.Strings[a.Attributes[j].ValueIndex]!=parsed.Bxml.Strings[b.Attributes[j].ValueIndex]) attributeChanges++;
            }
        }
        if(attributeChanges!=currencyChanges.Count) throw new InvalidDataException("Unexpected state mutation count");
        foreach(var row in root.GetProperty("Entries").EnumerateArray()) {
            var payload=parsed.Binary.Records[record.Ordinal].Payload; int p=Locate(payload,row.GetProperty("CollectionItemId").GetString()!);
            if(payload[p+40]!=1 || BitConverter.ToUInt32(payload,p+42)!=row.GetProperty("TargetProgress").GetUInt32()) throw new InvalidDataException("Completion verification failed");
        }
        File.WriteAllBytes(output,edited);
        File.WriteAllText(reportPath,JsonSerializer.Serialize(new {SourceSHA256=Digest(original),EditedSHA256=Digest(edited),Entries=changed,CurrencyChanges=currencyChanges,UneditedRoundtripExact=true,EditedRoundtripExact=true,PropertiesUnchanged=true,DatabaseUnchanged=true,OtherBinaryRecordsUnchanged=true,BxmlAttributeChanges=attributeChanges,GameLoadVerified=false},new JsonSerializerOptions{WriteIndented=true}));
    }
}
