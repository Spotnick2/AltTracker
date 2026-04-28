using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using MoonSharp.Interpreter;

namespace AltTracker.RenderPipeline.Services;

public sealed class SavedVariablesCharacterSource
{
    public IReadOnlyList<CharacterRecord> LoadCharacters(string filePath, RunLogger logger)
    {
        Script.WarmUp();
        var script = new Script(CoreModules.Preset_HardSandbox);
        var lua = File.ReadAllText(filePath);
        try
        {
            script.DoString(lua);
        }
        catch (Exception ex)
        {
            throw new PipelineDataException(
                $"Failed to parse SavedVariables input at '{filePath}': {ex.Message}. " +
                "InputDataPath must point to the AltTracker SavedVariables file (WTF\\Account\\...\\SavedVariables\\AltTracker.lua), not addon source files.");
        }

        var db = script.Globals.Get("AltTrackerDB");
        if (db.Type != DataType.Table)
        {
            throw new PipelineDataException("AltTrackerDB table not found in input file.");
        }

        var sourceTable = db.Table!;
        var nested = sourceTable.Get("characters");
        if (nested.Type == DataType.Table)
        {
            sourceTable = nested.Table!;
        }

        var list = new List<CharacterRecord>();
        foreach (var pair in sourceTable.Pairs)
        {
            if (pair.Value.Type != DataType.Table) continue;
            var t = pair.Value.Table!;
            var name = ReadString(t, "name");
            if (string.IsNullOrWhiteSpace(name)) continue;

            var race = ReadString(t, "race");
            var faction = ReadString(t, "faction");
            if (string.IsNullOrWhiteSpace(faction))
            {
                faction = race switch
                {
                    "Human" or "Dwarf" or "Gnome" or "NightElf" or "Draenei" => "Alliance",
                    "Orc" or "Troll" or "Tauren" or "Scourge" or "BloodElf" => "Horde",
                    _ => ""
                };
            }

            var gearIds = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            var gearLinks = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            foreach (var slot in CharacterRecord.GearSlots)
            {
                var id = ReadInt(t, $"gearid_{slot}");
                var link = ReadString(t, $"gearlink_{slot}");
                if (id <= 0)
                {
                    id = PathTools.ExtractItemId(link);
                }
                if (id > 0) gearIds[slot] = id;
                if (!string.IsNullOrWhiteSpace(link)) gearLinks[slot] = link;
            }

            var record = new CharacterRecord
            {
                Guid = ReadString(t, "guid"),
                Name = name,
                Realm = ReadString(t, "realm"),
                Account = ReadString(t, "account"),
                Faction = faction,
                Race = race,
                Gender = ReadString(t, "gender"),
                Class = ReadString(t, "class"),
                Level = ReadInt(t, "level"),
                LastUpdateEpoch = ReadLong(t, "lastUpdate"),
                GearItemIds = gearIds,
                GearLinks = gearLinks
            };

            list.Add(record);
        }

        logger.Verbose($"Loaded {list.Count} characters from SavedVariables.");
        return list;
    }

    private static string ReadString(Table table, string key)
    {
        var v = table.Get(key);
        return v.Type switch
        {
            DataType.String => v.String ?? "",
            DataType.Number => v.Number.ToString(),
            DataType.Boolean => v.Boolean ? "true" : "false",
            _ => ""
        };
    }

    private static int ReadInt(Table table, string key)
    {
        var v = table.Get(key);
        if (v.Type == DataType.Number) return (int)v.Number;
        if (v.Type == DataType.String && int.TryParse(v.String, out var i)) return i;
        return 0;
    }

    private static long ReadLong(Table table, string key)
    {
        var v = table.Get(key);
        if (v.Type == DataType.Number) return (long)v.Number;
        if (v.Type == DataType.String && long.TryParse(v.String, out var l)) return l;
        return 0;
    }
}
