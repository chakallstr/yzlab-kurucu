using System.Text.Json;
using System.Text.Json.Serialization;

namespace YzlabKurucu;

/// Sunucudaki kurulum manifesti. Model / token alan adi / Node adresi degisirse
/// SADECE sunucudaki JSON duzenlenir — yeni surum dagitmaya gerek kalmaz.
public sealed partial class Manifest
{
    public const string Url = "https://yapayzekalab.org/kurulum/codex.json";

    [JsonPropertyName("schemaVersion")] public int SchemaVersion { get; set; }
    [JsonPropertyName("api")] public ApiInfo Api { get; set; } = new();
    [JsonPropertyName("codex")] public CodexInfo Codex { get; set; } = new();
    [JsonPropertyName("node")] public NodeInfo Node { get; set; } = new();

    public sealed class ApiInfo
    {
        [JsonPropertyName("baseUrl")] public string BaseUrl { get; set; } = "";
        [JsonPropertyName("validateUrl")] public string ValidateUrl { get; set; } = "";
        [JsonPropertyName("authPrefix")] public string AuthPrefix { get; set; } = "Bearer ";
        [JsonPropertyName("keyPrefix")] public string KeyPrefix { get; set; } = "yzk_live_";
    }

    public sealed class ModelInfo
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("label")] public string Label { get; set; } = "";
        [JsonPropertyName("contextWindow")] public int ContextWindow { get; set; }
        public override string ToString() => Label;
    }

    public sealed class CodexInfo
    {
        [JsonPropertyName("npmPackage")] public string NpmPackage { get; set; } = "";
        [JsonPropertyName("catalogUrl")] public string CatalogUrl { get; set; } = "";
        [JsonPropertyName("catalogFile")] public string CatalogFile { get; set; } = "";
        [JsonPropertyName("profileName")] public string ProfileName { get; set; } = "";
        [JsonPropertyName("profileFile")] public string ProfileFile { get; set; } = "";
        [JsonPropertyName("defaultModel")] public string DefaultModel { get; set; } = "";
        [JsonPropertyName("models")] public List<ModelInfo> Models { get; set; } = new();
        [JsonPropertyName("profileTemplate")] public string ProfileTemplate { get; set; } = "";
        [JsonPropertyName("tokenField")] public string TokenField { get; set; } = "";
    }

    public sealed class NodePlatform
    {
        [JsonPropertyName("url")] public string Url { get; set; } = "";
        [JsonPropertyName("silentArgs")] public string SilentArgs { get; set; } = "";
    }

    public sealed class NodeInfo
    {
        [JsonPropertyName("windows")] public NodePlatform Windows { get; set; } = new();
    }

    /// Once sunucudan cek; ulasilamazsa gomulu surume dus (internet kesintisinde de kurulsun).
    public static async Task<(Manifest, bool canli)> LoadAsync()
    {
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            var json = await http.GetStringAsync(Url);
            var m = JsonSerializer.Deserialize<Manifest>(json);
            if (m is not null && m.Codex.Models.Count > 0) return (m, true);
        }
        catch { /* gomuluye dusulur */ }
        return (Embedded, false);
    }

    public static Manifest Embedded =>
        JsonSerializer.Deserialize<Manifest>(EmbeddedJson)
        ?? throw new InvalidOperationException("gomulu manifest bozuk — build hatasi");
}
