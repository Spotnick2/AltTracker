using AltTracker.RenderPipeline.Models;
using System.Text.RegularExpressions;

namespace AltTracker.RenderPipeline.Services.HeroShot;

public static class HeroShotPromptBuilder
{
    private static readonly Regex ItemLinkNameRegex = new(@"\|h\[(?<name>[^\]]+)\]\|h", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    public static string Build(CharacterRecord character, string stylePreset, bool hasReferenceImage = false)
    {
        var race   = character.Race   ?? "";
        var gender = character.Gender ?? "";
        var cls    = character.Class  ?? "";

        var hasMainHandGear = character.GearItemIds.TryGetValue("mainhand", out var mainHandId) && mainHandId > 0;
        var hasOffHandGear = character.GearItemIds.TryGetValue("offhand", out var offHandId) && offHandId > 0;
        var hasRangedGear = character.GearItemIds.TryGetValue("ranged", out var rangedId) && rangedId > 0;

        var directive      = BuildDirective(stylePreset, hasReferenceImage);
        var subject        = BuildSubject(race, gender, cls);
        var raceDetails    = BuildRaceDetails(race, gender);
        var classHint      = BuildClassHint(cls, hasRangedGear);
        var weaponHint     = BuildWeaponHint(character, cls, hasReferenceImage, hasMainHandGear, hasOffHandGear);
        var petHint        = BuildPetHint(cls, hasReferenceImage);
        var genderPronoun  = gender.Equals("Male", StringComparison.OrdinalIgnoreCase) ? "He" : "She";
        var background     = BuildBackground(cls);
        var styleDesc      = BuildStyleDescription(stylePreset);

        var petSection = string.IsNullOrEmpty(petHint) ? "" : $"{petHint} ";

        return $"{directive} " +
               $"{subject}. " +
               $"{raceDetails} " +
               $"{genderPronoun} stands in a confident heroic three-quarter pose, {classHint}. " +
               $"{weaponHint} " +
               $"{petSection}" +
               $"Background: {background} " +
               $"{styleDesc}. " +
               "No text, no nameplate, no UI elements, no watermarks, no floating icons.";
    }

    // ── Directive ─────────────────────────────────────────────────────────────

    private static string BuildDirective(string stylePreset, bool hasReferenceImage)
    {
        var action = stylePreset.ToLowerInvariant() switch
        {
            "wow-like"   => "Generate a World of Warcraft style fantasy portrait.",
            "cartoonish" => "Generate a stylized cartoon fantasy portrait.",
            _            => "Generate a highly detailed photorealistic fantasy portrait.",
        };
        if (hasReferenceImage)
            return $"{action} " +
                   "The provided screenshot shows the desired composition and depth-of-field style: " +
                   "the character is rendered in sharp focus and fills most of the frame, " +
                   "while the background is heavily blurred with soft bokeh, exactly like the WoW character selection screen. " +
                   "Reproduce that same framing and depth-of-field treatment. " +
                   "Use the screenshot as a reference for the character's appearance, gear, race, facial features, and weapons. " +
                   "Weapon setup must match the screenshot silhouette exactly. " +
                   "If a one-handed weapon plus off-hand is shown, preserve that and do not replace it with a staff. " +
                   "Do NOT reproduce the specific background scenery or environment from the screenshot — " +
                   "replace it with the atmospheric class-color backdrop described below.";
        return action;
    }

    // ── Subject ───────────────────────────────────────────────────────────────

    private static string BuildSubject(string race, string gender, string cls)
    {
        var raceDesc = BuildRaceDescription(race, gender);
        return $"Subject: A heroic {raceDesc} {cls} from World of Warcraft: The Burning Crusade Classic";
    }

    private static string BuildRaceDescription(string race, string gender)
    {
        var g = gender.Equals("Male", StringComparison.OrdinalIgnoreCase) ? "male" : "female";
        return race.ToLowerInvariant() switch
        {
            "troll"     => $"{g} Troll",
            "night elf" => $"{g} Night Elf",
            "human"     => $"{g} Human",
            "dwarf"     => $"stout {g} Dwarf",
            "gnome"     => $"small {g} Gnome",
            "draenei"   => $"{g} Draenei",
            "orc"       => $"{g} Orc",
            "undead"    => $"{g} Undead",
            "tauren"    => $"large {g} Tauren",
            "blood elf" => $"{g} Blood Elf",
            _           => $"{g} {race}",
        };
    }

    private static string BuildRaceDetails(string race, string gender)
    {
        var pronoun = gender.Equals("Male", StringComparison.OrdinalIgnoreCase) ? "He has" : "She has";
        return race.ToLowerInvariant() switch
        {
            "troll"     => $"{pronoun} teal-green skin, short tusks, and a distinctive spiked mohawk hairstyle.",
            "night elf" => $"{pronoun} purple skin, long pointed ears, silver hair, and glowing eyes.",
            "draenei"   => $"{pronoun} blue skin, horns, and a tail.",
            "orc"       => $"{pronoun} green skin, prominent tusks, and a muscular build.",
            "undead"    => $"{pronoun} decaying skeletal features, exposed bones, and tattered flesh.",
            "tauren"    => $"{pronoun} bovine horns, a broad snout, and a massive muscular frame.",
            "blood elf" => $"{pronoun} golden glowing eyes, elegant features, and long pointed ears.",
            "gnome"     => $"{pronoun} a small stature, large curious eyes, and colorful hair.",
            "dwarf"     => $"{pronoun} a broad beard, stocky build, and sturdy features.",
            _           => "",
        };
    }

    // ── Class hint (gear/weapon silhouette) ───────────────────────────────────

    private static string BuildClassHint(string cls, bool hasRangedGear = false)
    {
        var rangedNote = hasRangedGear
            ? " — importantly, the character must be depicted with their ranged weapon (bow, gun, or crossbow) either held in hand or slung across their back, as hunters always carry their ranged weapon even if it is not visible on the character selection screen"
            : " carrying a hunter's bow or crossbow";

        return cls.ToLowerInvariant() switch
        {
            "hunter"       => $"wearing tier-quality mail armor with heavy pauldrons{rangedNote}",
            "warrior"      => "wearing heavy plate armor, carrying a sword and shield or large two-handed weapon",
            "paladin"      => "wearing gleaming plate armor with holy light accents, carrying a blessed weapon",
            "priest"       => "wearing flowing holy robes with radiant holy accents",
            "mage"         => "wearing arcane robes with runic patterns and arcane focus accents",
            "warlock"      => "wearing dark shadow-infused robes, with fel energy swirling around them",
            "druid"        => "wearing leather armor with nature motifs and wooden accents",
            "rogue"        => "wearing dark supple leather armor, wielding twin daggers",
            "shaman"       => "wearing mail armor adorned with totems and elemental runes",
            "death knight" => "wearing dark runed plate armor, wielding a two-handed runeblade",
            "monk"         => "wearing light leather wraps, in a martial arts stance",
            "demon hunter" => "wearing minimal fel-infused plate, wielding warglaives",
            "evoker"       => "wearing draconic scale armor, with draconic energy swirling around their hands",
            _              => "wearing class-appropriate armor",
        };
    }

    private static string BuildWeaponHint(
        CharacterRecord character,
        string cls,
        bool hasReferenceImage,
        bool hasMainHandGear,
        bool hasOffHandGear)
    {
        var mainName = TryExtractItemName(character, "mainhand");
        var offName = TryExtractItemName(character, "offhand");
        var mainType = InferMainHandType(mainName);
        var offType = InferOffHandType(offName);

        if (hasMainHandGear && hasOffHandGear)
        {
            var mainDesc = string.IsNullOrWhiteSpace(mainType)
                ? "a one-handed weapon"
                : $"a one-handed {mainType}";
            var offDesc = string.IsNullOrWhiteSpace(offType)
                ? "a distinct off-hand item"
                : $"a {offType}";

            if (cls.Equals("priest", StringComparison.OrdinalIgnoreCase) && string.IsNullOrWhiteSpace(mainType))
            {
                mainDesc = "an ornate one-handed holy mace or similar one-handed caster weapon";
            }

            var source = hasReferenceImage
                ? "Preserve the exact mace-and-offhand silhouette from the screenshot when visible."
                : "Preserve this one-hand plus off-hand silhouette from equipped slots.";

            return $"Weapon setup: {mainDesc} in the main hand and {offDesc} in the off hand. Do not depict a staff or any other two-handed weapon for this setup. {source}";
        }

        if (hasMainHandGear)
        {
            var mainDesc = string.IsNullOrWhiteSpace(mainType) ? "a class-appropriate weapon" : $"{mainType} weaponry";
            var source = hasReferenceImage
                ? "Preserve the exact weapon silhouette from the screenshot."
                : "Preserve the equipped weapon silhouette.";
            return $"Weapon setup: use {mainDesc} in hand. Do not invent an off-hand item unless it is clearly shown in the screenshot. {source}";
        }

        if (hasOffHandGear)
        {
            var offDesc = string.IsNullOrWhiteSpace(offType) ? "an off-hand focus item" : $"an off-hand {offType}";
            return $"Weapon setup: include {offDesc} and a compatible one-handed main-hand weapon. Do not use a staff silhouette.";
        }

        return hasReferenceImage
            ? "Weapon setup: match the screenshot weapon silhouette exactly."
            : "Weapon setup: use class-appropriate weapon silhouettes consistent with WoW TBC gear.";
    }

    private static string TryExtractItemName(CharacterRecord character, string slot)
    {
        if (!character.GearLinks.TryGetValue(slot, out var link) || string.IsNullOrWhiteSpace(link))
            return "";
        var match = ItemLinkNameRegex.Match(link);
        return match.Success ? match.Groups["name"].Value.Trim() : "";
    }

    private static string InferMainHandType(string itemName)
    {
        var text = itemName.ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(text)) return "";
        if (ContainsAny(text, "staff", "stave")) return "staff";
        if (ContainsAny(text, "mace", "hammer", "gavel", "maul")) return "mace";
        if (ContainsAny(text, "sword", "blade", "saber", "rapier")) return "sword";
        if (ContainsAny(text, "dagger", "shiv", "dirk", "stiletto", "kris")) return "dagger";
        if (ContainsAny(text, "axe", "hatchet", "cleaver")) return "axe";
        if (ContainsAny(text, "fist", "claw", "gauntlet")) return "fist weapon";
        if (ContainsAny(text, "polearm", "halberd", "glaive", "spear")) return "polearm";
        return "";
    }

    private static string InferOffHandType(string itemName)
    {
        var text = itemName.ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(text)) return "";
        if (ContainsAny(text, "shield", "aegis", "bulwark", "protector")) return "shield";
        if (ContainsAny(text, "orb", "focus", "tome", "book", "lantern", "idol", "totem", "libram", "relic")) return "magical focus";
        return "off-hand item";
    }

    private static bool ContainsAny(string text, params string[] needles)
    {
        foreach (var needle in needles)
        {
            if (text.Contains(needle, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    // ── Pet hint ──────────────────────────────────────────────────────────────

    /// <summary>
    /// For pet classes, generates a sentence instructing the AI to include the companion.
    /// When a reference image is provided, defers to whatever pet is visible in it.
    /// </summary>
    private static string BuildPetHint(string cls, bool hasReferenceImage) =>
        cls.ToLowerInvariant() switch
        {
            "hunter" => hasReferenceImage
                ? "A loyal beast companion (wolf, cat, raptor, bear, or similar WoW hunter pet) may be visible in the reference image — if so, include it faithfully. If not visible, optionally place a beast companion nearby in a supporting role."
                : "A loyal beast companion (wolf, cat, raptor, bear, or similar WoW hunter pet) stands or crouches nearby in a supporting role.",
            "warlock" => hasReferenceImage
                ? "A demonic familiar may be visible in the reference image — if so, include it faithfully (imp, voidwalker, succubus, felhunter, or felguard). If not visible, optionally show a subtle demonic presence near the warlock."
                : "A demonic familiar accompanies the warlock — an imp, voidwalker, succubus, or felhunter hovering or standing nearby.",
            _ => "",
        };

    // ── Background ────────────────────────────────────────────────────────────

    /// <summary>
    /// Returns an atmospheric background description using the class color tint.
    /// The background is deliberately low-detail and subdued so it reads well
    /// as a UI backdrop behind character icons and overlays.
    /// </summary>
    private static string BuildBackground(string cls)
    {
        var (colorName, hex) = GetClassColor(cls);
        return
            $"The character is placed against a subdued fantasy backdrop with heavy depth-of-field blur, " +
            $"soft bokeh haze, and a muted desaturated grey base tone subtly tinted with the character's " +
            $"official class color ({colorName}, {hex}). " +
            "The background is low-detail, moody, and atmospheric — no sharp scenery, no strong environmental storytelling, " +
            "no busy props. The environment should feel like a soft-focus game-cinematic backdrop: " +
            "vague silhouettes of fantasy architecture or landscape at most, rendered in deep shadow. " +
            "The background must remain clearly secondary to the character and must not reproduce the source screenshot environment.";
    }

    // ── Style ─────────────────────────────────────────────────────────────────

    private static string BuildStyleDescription(string stylePreset) =>
        stylePreset.ToLowerInvariant() switch
        {
            "wow-like"   => "Semi-realistic World of Warcraft style, vibrant saturated colors, heroic proportions, detailed painterly rendering",
            "cartoonish" => "Stylized cartoon art, bold clean outlines, vibrant saturated colors, exaggerated heroic proportions",
            _            => "Photorealistic high-fantasy concept art, cinematic dramatic lighting, highly detailed armor and skin textures, 8K quality render",
        };

    // ── Class color map ───────────────────────────────────────────────────────

    /// <summary>
    /// Returns the official WoW class color as (human-readable name, hex string).
    /// </summary>
    public static (string Name, string Hex) GetClassColor(string cls) =>
        cls.ToLowerInvariant() switch
        {
            "warrior"      => ("Tan Gold",         "#C79C6E"),
            "paladin"      => ("Pink",              "#F58CBA"),
            "hunter"       => ("Olive Green",       "#ABD473"),
            "rogue"        => ("Yellow",            "#FFF569"),
            "priest"       => ("White",             "#FFFFFF"),
            "death knight" => ("Crimson Red",       "#C41F3B"),
            "shaman"       => ("Electric Blue",     "#0070DE"),
            "mage"         => ("Sky Blue",          "#69CCF0"),
            "warlock"      => ("Muted Purple",      "#9482C9"),
            "monk"         => ("Jade Green",        "#00FF96"),
            "druid"        => ("Burnt Orange",      "#FF7D0A"),
            "demon hunter" => ("Violet Purple",     "#A330C9"),
            "evoker"       => ("Teal",              "#33937F"),
            _              => ("Neutral Grey",      "#808080"),
        };
}

