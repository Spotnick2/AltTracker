using System.Diagnostics;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using AltTracker.RenderPipeline.Infrastructure;
using AltTracker.RenderPipeline.Models;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Advanced;

namespace AltTracker.RenderPipeline.Services;

public sealed class WowConverterRenderAdapter : IRenderAdapter
{
    private const string DefaultCaptureScriptName = "wowconverter-capture-viewer.js";

    public RenderAdapterResult Execute(
        IReadOnlyList<RenderJob> jobs,
        AppConfig config,
        CliOptions options,
        RunLogger logger)
    {
        Directory.CreateDirectory(config.TempPath);
        Directory.CreateDirectory(config.RenderStagingPath);
        Directory.CreateDirectory(config.OutputRenderDirectory);

        var sourceByJob = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var errorByJob = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        if ((config.WowConverter.DryRunValidateEndpoints || !options.DryRun) && !CheckConverterAvailability(config, jobs, logger, out var availabilityError))
        {
            logger.Error(availabilityError);
            foreach (var job in jobs)
            {
                errorByJob[job.JobKey] = availabilityError;
            }
            return new RenderAdapterResult(sourceByJob, errorByJob);
        }

        foreach (var job in jobs)
        {
            try
            {
                logger.Info($"[wow-converter] job={job.JobKey} manifest={job.ManifestKey}");
                var inputResolution = ResolveConverterInput(job, config.WowConverter);
                if (string.IsNullOrWhiteSpace(inputResolution.Input))
                {
                    var mappingError = "No wow-converter input mapping found (automatic mapping unavailable; provide InputOverrides or GlobalInputFallback with a Wowhead dressing-room URL).";
                    logger.Warn($"[wow-converter] {job.JobKey} failed: {mappingError}");
                    errorByJob[job.JobKey] = mappingError;
                    continue;
                }
                if (!TryResolveBaseReference(inputResolution.Input!, out var baseType, out var baseValue, out var baseResolveError))
                {
                    var invalidInput = $"Invalid wow-converter input ({inputResolution.Source}): {baseResolveError}";
                    logger.Error($"[wow-converter] {job.JobKey} failed: {invalidInput}");
                    errorByJob[job.JobKey] = invalidInput;
                    continue;
                }

                logger.Info($"[wow-converter] {job.JobKey} sourceCharacter name={job.Character.Name} key={job.ManifestKey} race={job.Character.Race} gender={job.Character.Gender} class={job.Character.Class}");
                var expectedRaceId = MapWowRaceId(job.Character.Race);
                var expectedGenderId = MapWowGenderId(job.Character.Gender);
                logger.Info($"[wow-converter] {job.JobKey} expectedWowExportRaceGender race={expectedRaceId} gender={expectedGenderId}");
                logger.Info($"[wow-converter] {job.JobKey} converterInputSource={inputResolution.Source}");
                var stagedPngPath = Path.Combine(config.RenderStagingPath, job.OutputBaseName + ".png");
                var expectedViewerUrl = BuildViewerUrl(config.WowConverter.ConverterUrl, job.OutputBaseName + ".mdx");
                var payload = BuildExportRequestPayload(baseType, baseValue, job.OutputBaseName, config.WowConverter);
                logger.Info($"[wow-converter] {job.JobKey} transformedInput type={payload.character.@base.type} value={payload.character.@base.value}");
                WriteDebugRequestPayload(config, job, payload, inputResolution, logger);

                logger.Info($"[wow-converter] {job.JobKey} input={inputResolution.Input}");
                logger.Info($"[wow-converter] {job.JobKey} expectedViewerUrl={expectedViewerUrl}");
                logger.Info($"[wow-converter] {job.JobKey} expectedPng={stagedPngPath}");
                logger.Info($"[wow-converter] {job.JobKey} identityValidation=enforced");

                if (options.DryRun)
                {
                    logger.Info($"[dry-run] wow-converter submit skipped for {job.JobKey}");
                    continue;
                }

                var submit = SubmitExportJob(config, payload);
                if (!submit.Success)
                {
                    var submitError = $"Export submit failed: {submit.Error}";
                    logger.Error($"[wow-converter] {job.JobKey} failed: {submitError}");
                    errorByJob[job.JobKey] = submitError;
                    continue;
                }

                logger.Info($"[wow-converter] {job.JobKey} exportJobId={submit.JobId}");
                var polled = PollExportStatus(config, submit.JobId!, logger, job.JobKey);
                if (!polled.Success)
                {
                    var pollError = $"Export poll failed: {polled.Error}";
                    logger.Error($"[wow-converter] {job.JobKey} failed: {pollError}");
                    errorByJob[job.JobKey] = pollError;
                    continue;
                }

                logger.Info($"[wow-converter] {job.JobKey} exportStatus={polled.Status}");
                var identityValidated = false;
                if (TryExtractWowExportRaceGender(polled.ObservedLogs, out var actualRaceId, out var actualGenderId))
                {
                    logger.Info($"[wow-converter] {job.JobKey} wowExportRaceGender expectedRace={expectedRaceId} expectedGender={expectedGenderId} actualRace={actualRaceId} actualGender={actualGenderId}");
                    if (expectedRaceId <= 0 || expectedGenderId < 0)
                    {
                        var mapping = $"Unable to map expected race/gender for validation (race={job.Character.Race}, gender={job.Character.Gender}).";
                        logger.Error($"[wow-converter] {job.JobKey} failed: {mapping}");
                        errorByJob[job.JobKey] = mapping;
                        continue;
                    }
                    if (actualRaceId != expectedRaceId || actualGenderId != expectedGenderId)
                    {
                        var mismatch = $"wow.export fallback/mismatch detected: expected race={expectedRaceId},gender={expectedGenderId} but got race={actualRaceId},gender={actualGenderId}. inputSource={inputResolution.Source}";
                        logger.Error($"[wow-converter] {job.JobKey} failed: {mismatch}");
                        errorByJob[job.JobKey] = mismatch;
                        continue;
                    }
                    identityValidated = true;
                }

                if (TryExtractBaseModelPath(polled.ObservedLogs, out var baseModelPath))
                {
                    logger.Info($"[wow-converter] {job.JobKey} exportedBaseModel={baseModelPath}");
                    if (!BaseModelMatchesCharacter(baseModelPath!, job.Character, out var mismatchReason))
                    {
                        var mismatch = $"Exported base model mismatch: {mismatchReason}";
                        logger.Error($"[wow-converter] {job.JobKey} failed: {mismatch}");
                        errorByJob[job.JobKey] = mismatch;
                        continue;
                    }
                }
                else if (!identityValidated)
                {
                    var noIdentity = "Unable to determine exported base model identity from wow-converter logs.";
                    logger.Error($"[wow-converter] {job.JobKey} failed: {noIdentity}");
                    errorByJob[job.JobKey] = noIdentity;
                    continue;
                }
                var modelPath = ResolveExportedModelPath(polled, config, job);
                if (string.IsNullOrWhiteSpace(modelPath))
                {
                    const string missingModelError = "Export succeeded but MDX output was not found.";
                    logger.Error($"[wow-converter] {job.JobKey} failed: {missingModelError}");
                    errorByJob[job.JobKey] = missingModelError;
                    continue;
                }

                logger.Info($"[wow-converter] {job.JobKey} exportedMdx={modelPath}");
                var modelValidation = ValidateExportedModel(polled, config, job, logger, modelPath!);
                if (!modelValidation.Success)
                {
                    logger.Error($"[wow-converter] {job.JobKey} failed: {modelValidation.Error}");
                    errorByJob[job.JobKey] = modelValidation.Error;
                    continue;
                }
                if (!TryReadExportedTextureCount(polled.RawResponse, out var exportedTextureCount))
                {
                    const string textureCountError = "Unable to determine exported texture count from wow-converter status response.";
                    logger.Error($"[wow-converter] {job.JobKey} failed: {textureCountError}");
                    errorByJob[job.JobKey] = textureCountError;
                    continue;
                }
                logger.Info($"[wow-converter] {job.JobKey} exportedTextureCount={exportedTextureCount}");
                if (exportedTextureCount <= 0)
                {
                    const string noTextures = "Exported texture count is zero (model likely untextured).";
                    logger.Error($"[wow-converter] {job.JobKey} failed: {noTextures}");
                    errorByJob[job.JobKey] = noTextures;
                    continue;
                }
                var viewerUrl = BuildViewerUrl(config.WowConverter.ConverterUrl, modelPath!);
                logger.Info($"[wow-converter] {job.JobKey} viewerUrl={viewerUrl}");

                var capture = CaptureViewerPng(config, stagedPngPath, viewerUrl, logger);
                if (!capture.Success)
                {
                    var captureError = $"Screenshot failed: {capture.Error}";
                    logger.Error($"[wow-converter] {job.JobKey} failed: {captureError}");
                    errorByJob[job.JobKey] = captureError;
                    continue;
                }

                if (!File.Exists(stagedPngPath))
                {
                    const string pngMissingError = "Screenshot completed but PNG was not created.";
                    logger.Error($"[wow-converter] {job.JobKey} failed: {pngMissingError}");
                    errorByJob[job.JobKey] = pngMissingError;
                    continue;
                }

                var fileInfo = new FileInfo(stagedPngPath);
                if (fileInfo.Length <= 0)
                {
                    const string pngEmptyError = "Screenshot PNG exists but is empty.";
                    logger.Error($"[wow-converter] {job.JobKey} failed: {pngEmptyError}");
                    errorByJob[job.JobKey] = pngEmptyError;
                    continue;
                }

                if (!ValidateCapturedImage(stagedPngPath, out var imageValidation))
                {
                    var validationError = $"Captured image rejected: {imageValidation}";
                    logger.Error($"[wow-converter] {job.JobKey} failed: {validationError}");
                    errorByJob[job.JobKey] = validationError;
                    continue;
                }
                logger.Info($"[wow-converter] {job.JobKey} imageValidation={imageValidation}");

                logger.Info($"[wow-converter] {job.JobKey} pngPath={stagedPngPath}");
                sourceByJob[job.JobKey] = stagedPngPath;
            }
            catch (Exception ex)
            {
                var error = ex.Message;
                logger.Error($"[wow-converter] {job.JobKey} failed: {error}");
                errorByJob[job.JobKey] = error;
            }
        }

        return new RenderAdapterResult(sourceByJob, errorByJob);
    }

    private static ConverterInputResolution ResolveConverterInput(RenderJob job, AppConfig.WowConverterConfig cfg)
    {
        if (TryGetOverride(cfg.InputOverrides, job.ManifestKey, out var manifestMatch))
            return ConverterInputResolution.Override(manifestMatch, $"inputOverride:manifestKey:{job.ManifestKey}");
        if (TryGetOverride(cfg.InputOverrides, job.OutputBaseName, out var baseNameMatch))
            return ConverterInputResolution.Override(baseNameMatch, $"inputOverride:outputBaseName:{job.OutputBaseName}");
        if (TryGetOverride(cfg.InputOverrides, job.Character.Name, out var nameMatch))
            return ConverterInputResolution.Override(nameMatch, $"inputOverride:characterName:{job.Character.Name}");

        // Automatic RenderJob->dressing-room generation is not implemented yet.
        if (!string.IsNullOrWhiteSpace(cfg.GlobalInputFallback))
            return ConverterInputResolution.GlobalFallback(cfg.GlobalInputFallback.Trim());

        return ConverterInputResolution.None("automatic-mapping-unavailable");
    }

    private static bool TryGetOverride(IReadOnlyDictionary<string, string>? map, string key, out string value)
    {
        value = "";
        if (map is null || map.Count == 0 || string.IsNullOrWhiteSpace(key)) return false;
        foreach (var pair in map)
        {
            if (!string.Equals(pair.Key?.Trim(), key.Trim(), StringComparison.OrdinalIgnoreCase)) continue;
            if (string.IsNullOrWhiteSpace(pair.Value)) return false;
            value = pair.Value.Trim();
            return true;
        }
        return false;
    }

    private static bool CheckConverterAvailability(AppConfig config, IReadOnlyList<RenderJob> jobs, RunLogger logger, out string error)
    {
        error = "";
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            var wowExportUrl = config.WowConverter.WowExportUrl;
            logger.Info($"[wow-export] preflight url={wowExportUrl}");
            if (TryResolveBackendProcessPath(wowExportUrl, out var wowExportPidPreflight, out var wowExportProcessPathPreflight))
            {
                logger.Info($"[wow-export] processId={wowExportPidPreflight} processPath={wowExportProcessPathPreflight}");
                var expectedBackendRoot = ResolveExpectedBackendRoot(config.WowConverter);
                if (!string.IsNullOrWhiteSpace(expectedBackendRoot)
                    && !Path.GetFullPath(wowExportProcessPathPreflight).StartsWith(expectedBackendRoot, StringComparison.OrdinalIgnoreCase))
                {
                    logger.Warn($"[wow-export] BACKEND PATH MISMATCH: active wow.export is '{wowExportProcessPathPreflight}' but configured wow-converter folder is '{expectedBackendRoot}'.");
                }
            }
            else
            {
                logger.Warn($"[wow-export] Unable to resolve active wow.export process path for {wowExportUrl}.");
            }

            var wowExportProbe = client.GetAsync($"{wowExportUrl}/rest/getCascInfo").GetAwaiter().GetResult();
            if (!wowExportProbe.IsSuccessStatusCode)
            {
                error = $"wow.export preflight failed: GET {wowExportUrl}/rest/getCascInfo returned {(int)wowExportProbe.StatusCode}. Start bundled wow.export.exe from your configured wow-converter folder, then load Local Installation + Anniversary/TBC build before running.";
                return false;
            }

            var cascRaw = wowExportProbe.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            logger.Verbose($"[wow-export] /rest/getCascInfo response={cascRaw}");
            if (!TryExtractCascInfo(cascRaw, out var casc))
            {
                error = $"wow.export preflight failed: unable to parse {wowExportUrl}/rest/getCascInfo. Ensure wow.export is initialized with a loaded WoW product/build.";
                return false;
            }

            if (string.IsNullOrWhiteSpace(casc.Product)
                || string.IsNullOrWhiteSpace(casc.Version)
                || string.IsNullOrWhiteSpace(casc.BuildName)
                || string.IsNullOrWhiteSpace(casc.BuildKey))
            {
                error = $"wow.export preflight failed: no loaded CASC product/build detected at {wowExportUrl}. Open bundled wow.export.exe and load Local Installation + Anniversary/TBC build.";
                return false;
            }

            logger.Info($"[wow-export] product={casc.Product} version={casc.Version} wowExportVersion={casc.WowExportVersion} locale={casc.Locale} buildName={casc.BuildName} buildKey={casc.BuildKey}");
            WarnOnProductMismatch(config, casc, logger);

            var expectedProduct = config.WowConverter.ExpectedWowExportProduct;
            if (!string.IsNullOrWhiteSpace(expectedProduct)
                && !ContainsIgnoreCase(casc.Product, expectedProduct)
                && !ContainsIgnoreCase(casc.BuildName, expectedProduct))
            {
                var mismatch = $"Expected wow.export product/build token '{expectedProduct}' but got product='{casc.Product}', buildName='{casc.BuildName}'.";
                if (config.WowConverter.RequireExpectedWowExportProduct)
                {
                    error = $"wow.export preflight failed: {mismatch}";
                    return false;
                }

                logger.Warn($"[wow-export] {mismatch}");
            }

            var expectedVersionContains = config.WowConverter.ExpectedWowExportVersionContains;
            if (!string.IsNullOrWhiteSpace(expectedVersionContains))
            {
                var candidate = $"{casc.WowExportVersion} {casc.Version}".Trim();
                if (!ContainsIgnoreCase(candidate, expectedVersionContains))
                {
                    var mismatch = $"Expected wow.export version token '{expectedVersionContains}' but got wowExportVersion='{casc.WowExportVersion}', cascVersion='{casc.Version}'.";
                    if (config.WowConverter.RequireExpectedWowExportProduct)
                    {
                        error = $"wow.export preflight failed: {mismatch}";
                        return false;
                    }

                    logger.Warn($"[wow-export] {mismatch}");
                }
            }

            if (ContainsIgnoreCase(casc.WowExportVersion, "0.2.1"))
            {
                var warning = $"Active wow.export appears to be 0.2.1 (wowExportVersion={casc.WowExportVersion}). Verify bundled wow.export from the configured wow-converter folder is being used.";
                if (config.WowConverter.RequireExpectedWowExportProduct)
                {
                    error = $"wow.export preflight failed: {warning}";
                    return false;
                }
                logger.Warn($"[wow-export] {warning}");
            }

            var converterProbe = client.GetAsync($"{config.WowConverter.ConverterUrl}/api/get-config").GetAwaiter().GetResult();
            if (!converterProbe.IsSuccessStatusCode)
            {
                error = $"wow-converter endpoint unavailable: GET {config.WowConverter.ConverterUrl}/api/get-config returned {(int)converterProbe.StatusCode}.";
                return false;
            }
            var converterRaw = converterProbe.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            logger.Verbose($"[wow-converter] /api/get-config response={converterRaw}");

            return true;
        }
        catch (Exception ex)
        {
            error = $"Backend preflight failed (wow.export={config.WowConverter.WowExportUrl}, wow-converter={config.WowConverter.ConverterUrl}): {ex.Message}";
            return false;
        }
    }

    private static SubmitResult SubmitExportJob(AppConfig config, ExportCharacterRequestPayload payload)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(config.WowConverter.ExportTimeoutSeconds) };

        var response = client.PostAsJsonAsync($"{config.WowConverter.ConverterUrl}/api/export/character", payload).GetAwaiter().GetResult();
        var raw = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        if (!response.IsSuccessStatusCode)
        {
            return SubmitResult.Fail($"HTTP {(int)response.StatusCode}: {raw}");
        }

        using var doc = JsonDocument.Parse(raw);
        if (!doc.RootElement.TryGetProperty("id", out var idNode))
        {
            return SubmitResult.Fail($"Missing export job id in response: {raw}");
        }

        var jobId = idNode.GetString();
        if (string.IsNullOrWhiteSpace(jobId))
        {
            return SubmitResult.Fail($"Export job id is empty: {raw}");
        }

        return SubmitResult.Ok(jobId);
    }

    private static PollResult PollExportStatus(AppConfig config, string jobId, RunLogger logger, string jobKey)
    {
        var deadline = DateTimeOffset.UtcNow.AddSeconds(config.WowConverter.ExportTimeoutSeconds);
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        var observedLogs = new List<string>();

        while (DateTimeOffset.UtcNow <= deadline)
        {
            var response = client.GetAsync($"{config.WowConverter.ConverterUrl}/api/export/character/status/{jobId}").GetAwaiter().GetResult();
            var raw = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            if (!response.IsSuccessStatusCode)
            {
                return PollResult.Fail($"HTTP {(int)response.StatusCode}: {raw}");
            }

            using var doc = JsonDocument.Parse(raw);
            var status = doc.RootElement.TryGetProperty("status", out var statusNode) ? statusNode.GetString() ?? "" : "";
            if (!string.IsNullOrWhiteSpace(status))
            {
                logger.Verbose($"[wow-converter] {jobKey} pollStatus={status}");
            }
            if (doc.RootElement.TryGetProperty("logs", out var logsNode) && logsNode.ValueKind == JsonValueKind.Array)
            {
                foreach (var entry in logsNode.EnumerateArray())
                {
                    var line = entry.GetString();
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    if (!observedLogs.Contains(line, StringComparer.Ordinal))
                    {
                        observedLogs.Add(line);
                        logger.Verbose($"[wow-converter] {jobKey} exportLog={line}");
                    }
                }
            }

            if (status.Equals("done", StringComparison.OrdinalIgnoreCase))
            {
                return PollResult.Ok("done", raw, observedLogs);
            }

            if (status.Equals("failed", StringComparison.OrdinalIgnoreCase))
            {
                return PollResult.Fail($"Export job failed: {raw}");
            }

            Thread.Sleep(config.WowConverter.PollIntervalMilliseconds);
        }

        return PollResult.Fail($"Timed out waiting for export job {jobId} after {config.WowConverter.ExportTimeoutSeconds}s.");
    }

    private static ExportCharacterRequestPayload BuildExportRequestPayload(string inputType, string inputValue, string outputBaseName, AppConfig.WowConverterConfig cfg) =>
        new()
        {
            character = new()
            {
                @base = new()
                {
                    type = inputType,
                    value = inputValue
                },
                inGameMovespeed = 270
            },
            outputFileName = outputBaseName,
            optimization = new()
            {
                sortSequences = true,
                allMaterialsUnshaded = false,
                removeUnusedVertices = true,
                removeUnusedNodes = true,
                removeUnusedMaterialsTextures = cfg.RemoveUnusedMaterialsTextures
            },
            format = "mdx",
            formatVersion = "1000",
            includeTextures = cfg.IncludeTextures
        };

    private static void WriteDebugRequestPayload(AppConfig config, RenderJob job, ExportCharacterRequestPayload payload, ConverterInputResolution inputResolution, RunLogger logger)
    {
        var debugDir = Path.Combine(config.TempPath, "wowconverter-debug");
        Directory.CreateDirectory(debugDir);
        var name = PathTools.SanitizeToken(job.Character.Name, "character");
        var key = PathTools.SanitizeToken(job.ManifestKey, "manifest");
        var file = Path.Combine(debugDir, $"{DateTimeOffset.UtcNow:yyyyMMdd_HHmmss}_{key}_{name}_request.json");
        var json = JsonSerializer.Serialize(new
        {
            manifestKey = job.ManifestKey,
            characterName = job.Character.Name,
            source = new
            {
                race = job.Character.Race,
                gender = job.Character.Gender,
                @class = job.Character.Class,
                gearItemIds = CharacterRecord.GearSlots.ToDictionary(slot => slot, slot => job.Character.GearItemIds.TryGetValue(slot, out var id) ? id : 0)
            },
            inputResolution,
            payload
        }, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(file, json);
        logger.Info($"[wow-converter] {job.JobKey} requestPayloadPath={file}");
    }

    private static bool TryResolveBaseReference(string rawInput, out string type, out string value, out string error)
    {
        type = "";
        value = "";
        error = "";
        var input = (rawInput ?? "").Trim();
        if (string.IsNullOrWhiteSpace(input))
        {
            error = "input is empty";
            return false;
        }

        var wowheadCharacterRegex = new Regex(@"^https:\/\/www\.wowhead\.com\/(?:[a-z-]+\/)?(npc=|item=|object=|dressing-room(\?.+)?#)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (wowheadCharacterRegex.IsMatch(input))
        {
            type = "wowhead";
            // Preserve namespace exactly as provided (/classic, /tbc, /wotlk, retail, etc).
            value = input;
            return true;
        }

        if (Regex.IsMatch(input, @"^\d+$", RegexOptions.CultureInvariant))
        {
            type = "displayID";
            value = input;
            return true;
        }

        var hasPathSeparators = input.Contains('\\') || input.Contains('/');
        var hasModelExtension = Regex.IsMatch(input, @"\.(obj|m2|wmo)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        var hasDrivePrefix = Regex.IsMatch(input, @"^[a-zA-Z]:[\\/]", RegexOptions.CultureInvariant);
        var isUnc = input.StartsWith(@"\\", StringComparison.Ordinal);
        var hasQuotes = input.StartsWith('"') || input.EndsWith('"');
        if ((hasModelExtension || hasPathSeparators || hasDrivePrefix || isUnc || hasQuotes))
        {
            type = "local";
            value = input.Trim('"');
            return true;
        }

        error = "unsupported input format; expected wowhead NPC/item/object/dressing-room URL, numeric displayID, or local OBJ/M2/WMO path";
        return false;
    }

    private static bool TryExtractBaseModelPath(IReadOnlyList<string> logs, out string? modelPath)
    {
        modelPath = null;
        foreach (var line in logs)
        {
            var marker = "Successfully exported ";
            var idx = line.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
            if (idx >= 0)
            {
                var pathPart = line[(idx + marker.Length)..].Trim();
                if (pathPart.EndsWith(".m2", StringComparison.OrdinalIgnoreCase))
                {
                    modelPath = pathPart.Replace("\\", "/", StringComparison.Ordinal);
                    return true;
                }
            }

            var m2Idx = line.IndexOf(".m2", StringComparison.OrdinalIgnoreCase);
            var charIdx = line.IndexOf("character/", StringComparison.OrdinalIgnoreCase);
            if (m2Idx > 0 && charIdx >= 0)
            {
                modelPath = line[charIdx..(m2Idx + 3)].Trim().Replace("\\", "/", StringComparison.Ordinal);
                return true;
            }
        }
        return false;
    }

    private static bool BaseModelMatchesCharacter(string baseModelPath, CharacterRecord character, out string reason)
    {
        reason = "";
        var normalized = baseModelPath.ToLowerInvariant();
        var expectedRace = NormalizeRaceToken(character.Race);
        var expectedGender = NormalizeGenderToken(character.Gender);
        if (string.IsNullOrWhiteSpace(expectedRace) || string.IsNullOrWhiteSpace(expectedGender))
        {
            reason = $"Cannot validate base model because expected race/gender token is missing (race={character.Race}, gender={character.Gender}).";
            return false;
        }

        var expectedPathToken = $"/character/{expectedRace}/{expectedGender}/";
        if (normalized.Contains(expectedPathToken, StringComparison.Ordinal))
        {
            return true;
        }

        reason = $"expected token '{expectedPathToken}' but got '{baseModelPath}'.";
        return false;
    }

    private static string NormalizeRaceToken(string race) =>
        (race ?? "").Trim().ToLowerInvariant() switch
        {
            "blood elf" => "bloodelf",
            "night elf" => "nightelf",
            "scourge" => "undead",
            _ => (race ?? "").Trim().ToLowerInvariant().Replace(" ", "", StringComparison.Ordinal)
        };

    private static string NormalizeGenderToken(string gender) =>
        (gender ?? "").Trim().ToLowerInvariant() switch
        {
            "male" => "male",
            "female" => "female",
            _ => ""
        };

    private static bool TryExtractWowExportRaceGender(IReadOnlyList<string> logs, out int raceId, out int genderId)
    {
        raceId = 0;
        genderId = -1;
        foreach (var line in logs)
        {
            var marker = "wow.export character - race:";
            var idx = line.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
            if (idx < 0) continue;
            var tail = line[(idx + marker.Length)..].Trim();
            // expected tail shape: "1 gender: 0"
            var parts = tail.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 3
                && int.TryParse(parts[0], out var parsedRace)
                && parts[1].StartsWith("gender", StringComparison.OrdinalIgnoreCase)
                && int.TryParse(parts[^1], out var parsedGender))
            {
                raceId = parsedRace;
                genderId = parsedGender;
                return true;
            }
        }
        return false;
    }

    private static int MapWowRaceId(string race) =>
        (race ?? "").Trim().ToLowerInvariant() switch
        {
            "human" => 1,
            "orc" => 2,
            "dwarf" => 3,
            "nightelf" => 4,
            "night elf" => 4,
            "scourge" => 5,
            "undead" => 5,
            "tauren" => 6,
            "gnome" => 7,
            "troll" => 8,
            "bloodelf" => 10,
            "blood elf" => 10,
            "draenei" => 11,
            _ => 0
        };

    private static int MapWowGenderId(string gender) =>
        (gender ?? "").Trim().ToLowerInvariant() switch
        {
            "male" => 0,
            "female" => 1,
            _ => -1
        };

    private static string? ResolveExportedModelPath(PollResult poll, AppConfig config, RenderJob job)
    {
        if (!poll.Success || string.IsNullOrWhiteSpace(poll.RawResponse)) return null;

        using var doc = JsonDocument.Parse(poll.RawResponse);
        var root = doc.RootElement;
        if (root.TryGetProperty("result", out var resultNode))
        {
            if (resultNode.TryGetProperty("exportedModels", out var modelsNode) && modelsNode.ValueKind == JsonValueKind.Array)
            {
                foreach (var model in modelsNode.EnumerateArray())
                {
                    if (!model.TryGetProperty("path", out var pathNode)) continue;
                    var relative = pathNode.GetString();
                    if (string.IsNullOrWhiteSpace(relative) || !relative.EndsWith(".mdx", StringComparison.OrdinalIgnoreCase)) continue;
                    return relative.Replace("\\", "/", StringComparison.Ordinal);
                }
            }

            if (resultNode.TryGetProperty("outputDirectory", out var outputDirNode))
            {
                var outputDir = outputDirNode.GetString();
                if (!string.IsNullOrWhiteSpace(outputDir))
                {
                    var fallback = FindExportedModelFromFilesystem(outputDir, job.OutputBaseName);
                    if (fallback is not null) return fallback;
                }
            }
        }

        return FindExportedModelFromFilesystem(config.WowConverter.ExportedAssetsPath, job.OutputBaseName);
    }

    private static bool TryReadExportedTextureCount(string rawResponse, out int count)
    {
        count = 0;
        if (string.IsNullOrWhiteSpace(rawResponse)) return false;
        try
        {
            using var doc = JsonDocument.Parse(rawResponse);
            if (!doc.RootElement.TryGetProperty("result", out var resultNode)) return false;
            if (!resultNode.TryGetProperty("exportedTextures", out var texturesNode)) return false;
            if (texturesNode.ValueKind != JsonValueKind.Array) return false;
            count = texturesNode.GetArrayLength();
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static ExportModelValidationResult ValidateExportedModel(
        PollResult poll,
        AppConfig config,
        RenderJob job,
        RunLogger logger,
        string modelPath)
    {
        var fullPath = Path.Combine(config.WowConverter.ExportedAssetsPath, modelPath.Replace("/", "\\", StringComparison.Ordinal));
        if (!File.Exists(fullPath))
        {
            return ExportModelValidationResult.Fail($"Exported MDX not found on disk: {fullPath}");
        }

        var fileInfo = new FileInfo(fullPath);
        logger.Info($"[wow-converter] {job.JobKey} exportedMdxSize={fileInfo.Length}");
        if (fileInfo.Length < 50_000)
        {
            return ExportModelValidationResult.Fail($"Exported MDX appears too small ({fileInfo.Length} bytes).");
        }

        if (string.IsNullOrWhiteSpace(poll.RawResponse))
        {
            return ExportModelValidationResult.Ok();
        }

        try
        {
            using var doc = JsonDocument.Parse(poll.RawResponse);
            if (!doc.RootElement.TryGetProperty("result", out var resultNode))
            {
                return ExportModelValidationResult.Ok();
            }
            if (!resultNode.TryGetProperty("modelStats", out var statsNode) || statsNode.ValueKind != JsonValueKind.Object)
            {
                return ExportModelValidationResult.Ok();
            }

            var geosets = ReadInt(statsNode, "geosets");
            var textures = ReadInt(statsNode, "textures");
            var vertices = ReadInt(statsNode, "vertices");
            var faces = ReadInt(statsNode, "faces");
            var sequences = ReadInt(statsNode, "sequences");
            var cameras = ReadInt(statsNode, "cameras");
            logger.Info($"[wow-converter] {job.JobKey} modelStats geosets={geosets} textures={textures} vertices={vertices} faces={faces} sequences={sequences} cameras={cameras}");

            if (geosets <= 0 || vertices <= 0 || faces <= 0)
            {
                return ExportModelValidationResult.Fail($"Model stats indicate empty model (geosets={geosets}, vertices={vertices}, faces={faces}).");
            }
        }
        catch (Exception ex)
        {
            logger.Warn($"[wow-converter] {job.JobKey} modelStats parse failed: {ex.Message}");
        }

        return ExportModelValidationResult.Ok();
    }

    private static string? FindExportedModelFromFilesystem(string rootPath, string outputBaseName)
    {
        if (string.IsNullOrWhiteSpace(rootPath) || !Directory.Exists(rootPath)) return null;
        var exact = Path.Combine(rootPath, outputBaseName + ".mdx");
        if (File.Exists(exact)) return Path.GetFileName(exact);

        var candidates = Directory.GetFiles(rootPath, outputBaseName + "*.mdx", SearchOption.AllDirectories);
        if (candidates.Length == 0) return null;
        var picked = candidates[0];
        var relative = Path.GetRelativePath(rootPath, picked);
        return relative.Replace("\\", "/", StringComparison.Ordinal);
    }

    private static string BuildViewerUrl(string converterUrl, string modelPath)
    {
        var normalized = (modelPath ?? "").Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
        return $"{converterUrl.TrimEnd('/')}/viewer?model={Uri.EscapeDataString(normalized)}";
    }

    private static CaptureResult CaptureViewerPng(AppConfig config, string outputPngPath, string viewerUrl, RunLogger logger)
    {
        var cfg = config.WowConverter;
        Directory.CreateDirectory(Path.GetDirectoryName(outputPngPath)!);
        var workingDir = Path.Combine(config.TempPath, "wowconverter-playwright");
        Directory.CreateDirectory(workingDir);

        var scriptPath = ResolveCaptureScriptPath(workingDir, cfg);
        var npxCommand = new StringBuilder();
        npxCommand.Append(cfg.NpxExecutable);
        npxCommand.Append(" --yes -p playwright ");
        npxCommand.Append(cfg.NodeExecutable);
        npxCommand.Append(" \"").Append(scriptPath).Append('"');
        npxCommand.Append(" --url \"").Append(viewerUrl).Append('"');
        npxCommand.Append(" --out \"").Append(outputPngPath).Append('"');
        npxCommand.Append(" --target \"").Append(cfg.CaptureTarget).Append('"');
        npxCommand.Append(" --width ").Append(cfg.ScreenshotWidth);
        npxCommand.Append(" --height ").Append(cfg.ScreenshotHeight);
        npxCommand.Append(" --wait-ms ").Append(cfg.ViewerWaitTimeoutSeconds * 1000);
        npxCommand.Append(" --transparent ").Append(cfg.PreferTransparentBackground ? "true" : "false");
        npxCommand.Append(" --background \"").Append(cfg.BackgroundColorFallback).Append('"');

        var npx = RunProcessCapture("cmd.exe", $"/c {npxCommand}", workingDir, "Playwright capture");
        if (!npx.Success)
        {
            return CaptureResult.Fail(npx.Error);
        }

        logger.Verbose($"[wow-converter] capture stdout: {npx.Stdout}");
        logger.Verbose($"[wow-converter] capture stderr: {npx.Stderr}");
        if (TryParseCaptureMetadata(npx.Stdout, out var meta))
        {
            logger.Info($"[wow-converter] canvasCount={meta.CanvasCount} selectedCanvas={meta.SelectedCanvasIndex} selectedCanvasSize={meta.SelectedCanvasWidth}x{meta.SelectedCanvasHeight} modelLoadSeen={meta.ModelLoadSeen} textureRequests={meta.TextureRequests} textureFailures={meta.TextureFailures}");
            if (meta.TextureRequests <= 0)
            {
                return CaptureResult.Fail("No texture asset requests observed in viewer.");
            }
            if (meta.TextureFailures > 0)
            {
                return CaptureResult.Fail($"Viewer reported texture asset request failures: {meta.TextureFailures}.");
            }
        }
        return CaptureResult.Ok();
    }

    private static bool TryParseCaptureMetadata(string stdout, out CaptureMetadata metadata)
    {
        metadata = new CaptureMetadata();
        if (string.IsNullOrWhiteSpace(stdout)) return false;
        var lines = stdout.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        foreach (var line in lines.Reverse())
        {
            if (!line.StartsWith("{", StringComparison.Ordinal) || !line.EndsWith("}", StringComparison.Ordinal)) continue;
            try
            {
                metadata = JsonSerializer.Deserialize<CaptureMetadata>(line, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new CaptureMetadata();
                return true;
            }
            catch
            {
                // ignore
            }
        }
        return false;
    }

    private static bool ValidateCapturedImage(string path, out string stats)
    {
        try
        {
            using var image = Image.Load<Rgba32>(path);
            var width = image.Width;
            var height = image.Height;
            var cropX = width / 5;
            var cropY = height / 6;
            var cropW = Math.Max(1, width - (cropX * 2));
            var cropH = Math.Max(1, height - (cropY * 2));

            var hist = new Dictionary<int, int>();
            long total = 0;
            long nonWhite = 0;
            long nonBlack = 0;
            long sumLuma = 0;
            double sumSaturation = 0;
            long saturatedPixels = 0;
            var step = Math.Max(1, Math.Min(cropW, cropH) / 120);

            for (var y = cropY; y < cropY + cropH; y += step)
            {
                var row = image.Frames.RootFrame.DangerousGetPixelRowMemory(y).Span;
                for (var x = cropX; x < cropX + cropW; x += step)
                {
                    var px = row[x];
                    var qR = px.R / 16;
                    var qG = px.G / 16;
                    var qB = px.B / 16;
                    var key = (qR << 8) | (qG << 4) | qB;
                    hist[key] = hist.TryGetValue(key, out var c) ? c + 1 : 1;

                    var luma = (px.R * 299 + px.G * 587 + px.B * 114) / 1000;
                    sumLuma += luma;
                    var max = Math.Max(px.R, Math.Max(px.G, px.B));
                    var min = Math.Min(px.R, Math.Min(px.G, px.B));
                    var sat = max == 0 ? 0d : (max - min) / (double)max;
                    sumSaturation += sat;
                    if (sat > 0.12d) saturatedPixels++;
                    total++;
                    if (!(px.R > 245 && px.G > 245 && px.B > 245)) nonWhite++;
                    if (!(px.R < 10 && px.G < 10 && px.B < 10)) nonBlack++;
                }
            }

            if (total == 0)
            {
                stats = "empty-sample";
                return false;
            }

            var unique = hist.Count;
            var dominant = hist.Values.Max();
            var dominantRatio = dominant / (double)total;
            var avgLuma = sumLuma / (double)total;
            var nonWhiteRatio = nonWhite / (double)total;
            var nonBlackRatio = nonBlack / (double)total;
            var avgSaturation = sumSaturation / total;
            var saturatedRatio = saturatedPixels / (double)total;

            stats = $"centerCrop={cropW}x{cropH}, samples={total}, unique={unique}, dominantRatio={dominantRatio:F3}, avgLuma={avgLuma:F1}, nonWhiteRatio={nonWhiteRatio:F3}, nonBlackRatio={nonBlackRatio:F3}, avgSaturation={avgSaturation:F3}, saturatedRatio={saturatedRatio:F3}";

            if (unique < 16) return false;
            if (dominantRatio > 0.97) return false;
            if (nonWhiteRatio < 0.04) return false;
            if (nonBlackRatio < 0.04) return false;
            // Reject mannequin-like captures that are mostly white/gray with little material color variance.
            if (avgSaturation < 0.07 && saturatedRatio < 0.04) return false;
            return true;
        }
        catch (Exception ex)
        {
            stats = $"image-parse-failed: {ex.Message}";
            return false;
        }
    }

    private static int ReadInt(JsonElement node, string name)
    {
        if (!node.TryGetProperty(name, out var e)) return 0;
        if (e.ValueKind == JsonValueKind.Number && e.TryGetInt32(out var i)) return i;
        if (e.ValueKind == JsonValueKind.String && int.TryParse(e.GetString(), out var p)) return p;
        return 0;
    }

    private static string ResolveCaptureScriptPath(string workingDir, AppConfig.WowConverterConfig cfg)
    {
        if (!string.IsNullOrWhiteSpace(cfg.PlaywrightScriptPath))
        {
            return cfg.PlaywrightScriptPath;
        }

        var path = Path.Combine(workingDir, DefaultCaptureScriptName);
        File.WriteAllText(path, BuildDefaultCaptureScript(), Encoding.UTF8);
        return path;
    }

    private static string BuildDefaultCaptureScript() =>
        """
        const { chromium } = require('playwright');
        
        function parseArgs(argv) {
          const map = {};
          for (let i = 2; i < argv.length; i += 1) {
            const key = argv[i];
            if (!key.startsWith('--')) continue;
            const value = argv[i + 1];
            map[key.slice(2)] = value;
            i += 1;
          }
          return map;
        }
        
        (async () => {
          const args = parseArgs(process.argv);
          const url = args.url;
          const out = args.out;
          const target = (args.target || 'canvas').toLowerCase();
          const width = Number(args.width || 1400);
          const height = Number(args.height || 1000);
          const waitMs = Number(args['wait-ms'] || 45000);
          const transparent = String(args.transparent || 'true').toLowerCase() === 'true';
          const background = args.background || '#141414';
        
          if (!url || !out) throw new Error('Missing --url or --out');
        
          const browser = await chromium.launch({ headless: true });
          const page = await browser.newPage({ viewport: { width, height } });
          let modelLoadSeen = false;
          let textureRequests = 0;
          let textureFailures = 0;
          const textureRegex = /\.(blp|dds|png|tga)(?:\?|$)/i;
         
          page.on('response', (r) => {
            const u = r.url().toLowerCase();
            if (u.includes('/api/assets/') && u.includes('.mdx') && r.status() >= 200 && r.status() < 300) {
              modelLoadSeen = true;
            }
            if (u.includes('/api/assets/') && textureRegex.test(u)) {
              textureRequests += 1;
              if (r.status() < 200 || r.status() >= 300) {
                textureFailures += 1;
              }
            }
          });

          page.on('requestfailed', (req) => {
            const u = req.url().toLowerCase();
            if (u.includes('/api/assets/') && textureRegex.test(u)) {
              textureRequests += 1;
              textureFailures += 1;
            }
          });
        
          await page.goto(url, { waitUntil: 'domcontentloaded', timeout: Math.max(waitMs, 10000) });
          await page.waitForSelector('canvas', { timeout: Math.max(waitMs, 10000) });
        
          if (!modelLoadSeen) {
            const modelResponse = await page.waitForResponse(
              (r) => {
                const u = r.url().toLowerCase();
                return u.includes('/api/assets/') && u.includes('.mdx') && r.status() >= 200 && r.status() < 300;
              },
              { timeout: Math.max(waitMs, 10000) }
            );
            if (!modelResponse) throw new Error('Model load response not observed.');
            modelLoadSeen = true;
          }
        
          if (!transparent) {
            await page.evaluate((bg) => {
              document.documentElement.style.background = bg;
              document.body.style.background = bg;
            }, background);
          }
        
          await page.waitForTimeout(1500);
        
          const canvases = await page.$$('canvas');
          if (!canvases || canvases.length === 0) throw new Error('No canvas elements found.');
        
          let selected = canvases[0];
          let selectedIdx = 0;
          let selectedArea = 0;
          let selectedW = 0;
          let selectedH = 0;
          for (let i = 0; i < canvases.length; i += 1) {
            const box = await canvases[i].boundingBox();
            if (!box) continue;
            const area = box.width * box.height;
            if (area > selectedArea) {
              selectedArea = area;
              selected = canvases[i];
              selectedIdx = i;
              selectedW = Math.round(box.width);
              selectedH = Math.round(box.height);
            }
          }
          if (selectedArea <= 0) throw new Error('No visible canvas with positive area found.');
        
          if (target === 'canvas') {
            await selected.screenshot({ path: out });
          } else {
            await page.screenshot({ path: out, fullPage: true });
          }
        
          console.log(JSON.stringify({
            canvasCount: canvases.length,
            selectedCanvasIndex: selectedIdx,
            selectedCanvasWidth: selectedW,
            selectedCanvasHeight: selectedH,
            modelLoadSeen,
            textureRequests,
            textureFailures
          }));
        
          await browser.close();
        })().catch((err) => {
          console.error(err && err.stack ? err.stack : String(err));
          process.exit(1);
        });
        """;

    private static ProcessResult RunProcessCapture(string fileName, string args, string workingDirectory, string operation)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = args,
                WorkingDirectory = workingDirectory,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(psi);
            if (process is null)
            {
                return ProcessResult.Fail($"{operation}: unable to start process {fileName}.", "", "");
            }

            var stdout = process.StandardOutput.ReadToEnd();
            var stderr = process.StandardError.ReadToEnd();
            process.WaitForExit();

            if (process.ExitCode != 0)
            {
                return ProcessResult.Fail($"{operation} failed: exit={process.ExitCode}, stderr={stderr}, stdout={stdout}", stdout, stderr);
            }

            return ProcessResult.Ok(stdout, stderr);
        }
        catch (Exception ex)
        {
            return ProcessResult.Fail($"{operation} failed to start: {ex.Message}", "", "");
        }
    }

    private sealed record SubmitResult(bool Success, string? JobId, string Error)
    {
        public static SubmitResult Ok(string jobId) => new(true, jobId, "");
        public static SubmitResult Fail(string error) => new(false, null, error);
    }

    private sealed record PollResult(bool Success, string Status, string RawResponse, string Error, IReadOnlyList<string> ObservedLogs)
    {
        public static PollResult Ok(string status, string rawResponse, IReadOnlyList<string> observedLogs) => new(true, status, rawResponse, "", observedLogs);
        public static PollResult Fail(string error) => new(false, "failed", "", error, Array.Empty<string>());
    }

    private sealed record CaptureResult(bool Success, string Error)
    {
        public static CaptureResult Ok() => new(true, "");
        public static CaptureResult Fail(string error) => new(false, error);
    }

    private sealed record ProcessResult(bool Success, string Error, string Stdout, string Stderr)
    {
        public static ProcessResult Ok(string stdout, string stderr) => new(true, "", stdout, stderr);
        public static ProcessResult Fail(string error, string stdout, string stderr) => new(false, error, stdout, stderr);
    }

    private sealed class CaptureMetadata
    {
        public int CanvasCount { get; set; }
        public int SelectedCanvasIndex { get; set; }
        public int SelectedCanvasWidth { get; set; }
        public int SelectedCanvasHeight { get; set; }
        public bool ModelLoadSeen { get; set; }
        public int TextureRequests { get; set; }
        public int TextureFailures { get; set; }
    }

    private sealed record ExportModelValidationResult(bool Success, string Error)
    {
        public static ExportModelValidationResult Ok() => new(true, "");
        public static ExportModelValidationResult Fail(string error) => new(false, error);
    }

    private sealed record ConverterInputResolution(string Mode, string Source, string Input, string Note)
    {
        public static ConverterInputResolution Override(string input, string source) => new("override", source, input, "");
        public static ConverterInputResolution GlobalFallback(string input) => new("global-fallback", "globalInputFallback", input, "");
        public static ConverterInputResolution None(string note) => new("none", "none", "", note);
    }

    private sealed class ExportCharacterRequestPayload
    {
        public required ExportCharacterBody character { get; init; }
        public required string outputFileName { get; init; }
        public required ExportOptimization optimization { get; init; }
        public required string format { get; init; }
        public required string formatVersion { get; init; }
        public bool includeTextures { get; init; }
    }

    private sealed class ExportCharacterBody
    {
        public required ExportBaseRef @base { get; init; }
        public int inGameMovespeed { get; init; }
    }

    private sealed class ExportBaseRef
    {
        public required string type { get; init; }
        public required string value { get; init; }
    }

    private sealed class ExportOptimization
    {
        public bool sortSequences { get; init; }
        public bool allMaterialsUnshaded { get; init; }
        public bool removeUnusedVertices { get; init; }
        public bool removeUnusedNodes { get; init; }
        public bool removeUnusedMaterialsTextures { get; init; }
    }

    private static bool TryExtractCascInfo(string rawJson, out CascInfo info)
    {
        info = new CascInfo();
        if (string.IsNullOrWhiteSpace(rawJson)) return false;
        try
        {
            using var doc = JsonDocument.Parse(rawJson);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return false;

            string Read(params string[] path)
            {
                var node = root;
                foreach (var part in path)
                {
                    if (!node.TryGetProperty(part, out node)) return "";
                }
                return node.ValueKind == JsonValueKind.String ? node.GetString() ?? "" : node.ToString();
            }

            static string FirstNonEmpty(params string[] values)
            {
                foreach (var value in values)
                {
                    if (!string.IsNullOrWhiteSpace(value)) return value;
                }
                return "";
            }

            var tags = Read("build", "Tags");
            var localeMatch = Regex.Match(tags ?? "", @"\b[a-z]{2}[A-Z]{2}\b", RegexOptions.CultureInvariant);
            info = new CascInfo
            {
                Product = FirstNonEmpty(Read("build", "Product"), Read("product")),
                Version = FirstNonEmpty(Read("build", "Version"), Read("version")),
                BuildKey = FirstNonEmpty(Read("build", "BuildKey"), Read("buildConfig", "buildKey"), Read("buildKey")),
                BuildName = FirstNonEmpty(Read("buildConfig", "buildName"), Read("buildName")),
                Locale = localeMatch.Success ? localeMatch.Value : ""
            };
            info = info with
            {
                WowExportVersion = FirstNonEmpty(
                    Read("app", "version"),
                    Read("wowExportVersion"),
                    Read("wowExport", "version"),
                    Read("serverVersion"))
            };
            if (string.IsNullOrWhiteSpace(info.Locale))
            {
                info = info with { Locale = FirstNonEmpty(Read("locale"), Read("build", "locale")) };
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static void WarnOnProductMismatch(AppConfig config, CascInfo casc, RunLogger logger)
    {
        var inputPath = (config.InputDataPath ?? "").ToLowerInvariant();
        var expectsClassicTbc = inputPath.Contains("_anniversary_", StringComparison.Ordinal)
                                || inputPath.Contains("_classic_tbc_", StringComparison.Ordinal)
                                || inputPath.Contains("classic", StringComparison.Ordinal);

        if (!expectsClassicTbc) return;

        var product = (casc.Product ?? "").ToLowerInvariant();
        var buildName = (casc.BuildName ?? "").ToLowerInvariant();
        var looksRetailOnly = product.Contains("retail", StringComparison.Ordinal)
                              && !product.Contains("classic", StringComparison.Ordinal)
                              && !buildName.Contains("classic", StringComparison.Ordinal)
                              && !buildName.Contains("tbc", StringComparison.Ordinal)
                              && !buildName.Contains("anniversary", StringComparison.Ordinal);

        if (looksRetailOnly)
        {
            logger.Warn("[wow-export] PRODUCT MISMATCH: source appears Classic/TBC context but wow.export reports retail-only product/build; identity checks remain enforced.");
            return;
        }

        var hasTbcSignal = buildName.Contains("tbc", StringComparison.Ordinal)
                           || buildName.Contains("anniversary", StringComparison.Ordinal);
        if (!hasTbcSignal)
        {
            logger.Warn("[wow-export] Classic/TBC source detected, but wow.export build does not clearly indicate TBC Anniversary. If available in your wow.export build, prefer the TBC Anniversary product/build.");
        }
    }

    private static bool ContainsIgnoreCase(string source, string token) =>
        !string.IsNullOrWhiteSpace(token)
        && !string.IsNullOrWhiteSpace(source)
        && source.Contains(token, StringComparison.OrdinalIgnoreCase);

    private static string ResolveExpectedBackendRoot(AppConfig.WowConverterConfig cfg)
    {
        if (!string.IsNullOrWhiteSpace(cfg.WowExportExecutablePath))
        {
            var root = Path.GetDirectoryName(Path.GetFullPath(cfg.WowExportExecutablePath));
            if (!string.IsNullOrWhiteSpace(root)) return root;
        }
        if (!string.IsNullOrWhiteSpace(cfg.ConverterExecutablePath))
        {
            var root = Path.GetDirectoryName(Path.GetFullPath(cfg.ConverterExecutablePath));
            if (!string.IsNullOrWhiteSpace(root)) return root;
        }
        return "";
    }

    private static bool TryResolveBackendProcessPath(string baseUrl, out int pid, out string processPath)
    {
        pid = 0;
        processPath = "";
        if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out var uri)) return false;
        if (!(uri.Host.Equals("127.0.0.1", StringComparison.OrdinalIgnoreCase)
              || uri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        var netstat = RunProcessCapture("cmd.exe", "/c netstat -ano -p tcp", Environment.CurrentDirectory, "Resolve wow.export process");
        if (!netstat.Success || string.IsNullOrWhiteSpace(netstat.Stdout)) return false;

        var lines = netstat.Stdout.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        foreach (var line in lines)
        {
            if (!line.Contains("LISTENING", StringComparison.OrdinalIgnoreCase)) continue;
            var parts = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 5) continue;
            var localAddress = parts[1];
            var state = parts[3];
            if (!state.Equals("LISTENING", StringComparison.OrdinalIgnoreCase)) continue;
            if (!localAddress.EndsWith($":{uri.Port}", StringComparison.Ordinal)) continue;
            if (!int.TryParse(parts[4], out var parsedPid) || parsedPid <= 0) continue;

            try
            {
                var process = Process.GetProcessById(parsedPid);
                var fileName = process.MainModule?.FileName;
                if (string.IsNullOrWhiteSpace(fileName)) return false;
                pid = parsedPid;
                processPath = Path.GetFullPath(fileName);
                return true;
            }
            catch
            {
                return false;
            }
        }

        return false;
    }

    private sealed record CascInfo
    {
        public string Product { get; init; } = "";
        public string Version { get; init; } = "";
        public string BuildName { get; init; } = "";
        public string BuildKey { get; init; } = "";
        public string Locale { get; init; } = "";
        public string WowExportVersion { get; init; } = "";
    }
}
