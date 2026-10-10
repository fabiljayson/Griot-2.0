using System.Globalization;
using Newtonsoft.Json;

// The JSON shapes exchanged with the Django VR API. Member names mirror
// backend/vr/serializers.py: JsonProperty maps the API's snake_case onto this
// project's PascalCase, so a serializer rename fails loudly here instead of
// silently in a headset.
//
// Deserialization is tolerant by design. A field the server does not send —
// an older backend, a column a curator left blank — arrives as null or its
// type default, and ExperienceContent falls back to the scene's local data
// rather than failing the load. No credential lives in any of these types;
// the bearer token is only ever held by Authentication.VRTokenStore.

namespace Griot.VR.Network
{
    /// <summary>The error body every Django VR endpoint returns on failure.</summary>
    public sealed class ApiErrorBody
    {
        /// <summary>Human-readable reason from the server.</summary>
        [JsonProperty("error")]
        public string Error;

        /// <summary>Stable machine code, e.g. <c>token_expired</c>.</summary>
        [JsonProperty("code")]
        public string Code;
    }

    /// <summary>Body of <c>POST /api/vr/launch/exchange/</c>.</summary>
    public sealed class LaunchExchangeRequest
    {
        [JsonProperty("token")]
        public string Token;

        [JsonProperty("device_model")]
        public string DeviceModel;

        public LaunchExchangeRequest(string token, string deviceModel)
        {
            Token = token;
            DeviceModel = deviceModel;
        }
    }

    /// <summary>
    /// Response of the exchange: a VR-scoped session token plus the full
    /// experience payload. The token itself is passed straight to
    /// <see cref="Authentication.VRTokenStore"/> and never logged.
    /// </summary>
    public sealed class LaunchExchangeResponse
    {
        [JsonProperty("access_token")]
        public string AccessToken;

        [JsonProperty("expires_in")]
        public int ExpiresIn;

        [JsonProperty("experience")]
        public ExperiencePayload Experience;
    }

    /// <summary>One experience as <c>GET /api/vr/experiences/{key}/</c> returns it.</summary>
    public sealed class ExperiencePayload
    {
        [JsonProperty("id")]
        public int Id;

        [JsonProperty("slug")]
        public string Slug;

        [JsonProperty("title")]
        public string Title;

        [JsonProperty("description")]
        public string Description;

        /// <summary>Scene name from the backend; must exist in the build.</summary>
        [JsonProperty("scene_identifier")]
        public string SceneIdentifier;

        [JsonProperty("thumbnail")]
        public string Thumbnail;

        [JsonProperty("language")]
        public string Language;

        [JsonProperty("environment")]
        public string Environment;

        [JsonProperty("museum_name")]
        public string MuseumName;

        [JsonProperty("region")]
        public string Region;

        [JsonProperty("culture")]
        public string Culture;

        [JsonProperty("updated_at")]
        public string UpdatedAt;

        [JsonProperty("artifact_count")]
        public int ArtifactCount;

        [JsonProperty("artifacts")]
        public PlacedArtifact[] Artifacts;

        /// <summary>
        /// Find an artifact by slug — the contract between the scene's
        /// <c>ArtifactSpawner</c> and Django — or by numeric id as a
        /// fallback. Returns null when the payload does not contain it.
        /// </summary>
        public PlacedArtifact FindArtifact(string key)
        {
            if (Artifacts == null || string.IsNullOrEmpty(key)) return null;

            foreach (var artifact in Artifacts)
            {
                if (artifact != null && string.Equals(key, artifact.Slug, System.StringComparison.Ordinal))
                {
                    return artifact;
                }
            }

            foreach (var artifact in Artifacts)
            {
                if (artifact == null) continue;
                var id = artifact.Id.ToString(CultureInfo.InvariantCulture);
                if (string.Equals(key, id, System.StringComparison.Ordinal)) return artifact;
            }

            return null;
        }
    }

    /// <summary>An artifact as placed in a scene — the artifact plus its placement.</summary>
    public sealed class PlacedArtifact
    {
        [JsonProperty("id")]
        public int Id;

        [JsonProperty("slug")]
        public string Slug;

        [JsonProperty("name")]
        public string Name;

        [JsonProperty("description")]
        public string Description;

        [JsonProperty("category")]
        public string Category;

        [JsonProperty("content_type")]
        public string ContentType;

        [JsonProperty("culture")]
        public string Culture;

        [JsonProperty("region")]
        public string Region;

        [JsonProperty("estimated_date")]
        public string EstimatedDate;

        [JsonProperty("materials")]
        public string Materials;

        [JsonProperty("dimensions")]
        public string Dimensions;

        [JsonProperty("image")]
        public string Image;

        [JsonProperty("museum_name")]
        public string MuseumName;

        [JsonProperty("floor")]
        public string Floor;

        [JsonProperty("display_case")]
        public string DisplayCase;

        /// <summary>Text for the Learn More expansion. Blank means "use the scene's local copy".</summary>
        [JsonProperty("historical_significance")]
        public string HistoricalSignificance;

        /// <summary>Provenance URL for Learn More. Blank means "use the scene's local copy".</summary>
        [JsonProperty("source_url")]
        public string SourceUrl;

        [JsonProperty("stories")]
        public StoryReference[] Stories;

        [JsonProperty("order")]
        public int Order;

        [JsonProperty("model_url")]
        public string ModelUrl;

        [JsonProperty("model_scale")]
        public float ModelScale;

        [JsonProperty("is_interactive")]
        public bool IsInteractive;

        // `narration` is part of the payload but consumed by the audio
        // milestone, so it is deliberately not modelled yet — Newtonsoft
        // ignores it until something does.
    }

    /// <summary>A published story attached to an artifact, as a reference only.</summary>
    public sealed class StoryReference
    {
        [JsonProperty("id")]
        public int Id;

        [JsonProperty("slug")]
        public string Slug;

        [JsonProperty("title")]
        public string Title;

        [JsonProperty("language")]
        public string Language;
    }

    /// <summary>Body of <c>POST/PATCH /api/vr/progress/</c>.</summary>
    public sealed class ProgressUpdateRequest
    {
        /// <summary>0.0–1.0, or omitted when only the viewed list changes.</summary>
        [JsonProperty("progress", NullValueHandling = NullValueHandling.Ignore)]
        public float? Progress;

        /// <summary>The reader's complete viewed-artifact list so far (replaces, not appends).</summary>
        [JsonProperty("artifacts_viewed")]
        public int[] ArtifactsViewed;

        public ProgressUpdateRequest(float? progress, int[] artifactsViewed)
        {
            Progress = progress;
            ArtifactsViewed = artifactsViewed;
        }
    }

    /// <summary>
    /// The outcome of one API call. This project hands results back rather
    /// than throwing, so every coroutine caller has one error path to render
    /// instead of a catch block per call site.
    /// </summary>
    public class ApiResult
    {
        /// <summary>True on a 2xx the app could read.</summary>
        public bool Ok;

        /// <summary>HTTP status, or 0 for transport-level failures (timeout, DNS).</summary>
        public long StatusCode;

        /// <summary>
        /// Stable machine code: the Django error <c>code</c> when the server
        /// answered (<c>token_expired</c>, <c>session_not_active</c>, …), or
        /// a client-side one — <c>timeout</c>, <c>network_unavailable</c>,
        /// <c>invalid_response</c>. Never logged with the token.
        /// </summary>
        public string ErrorCode;

        /// <summary>Technical detail for logs. User-facing copy is written by AuthManager.</summary>
        public string Message;

        /// <summary>Raw response body, for diagnostics only. Never logged wholesale.</summary>
        public string Body;
    }

    /// <summary>An <see cref="ApiResult"/> carrying a deserialised payload on success.</summary>
    public sealed class ApiResult<T> : ApiResult
    {
        public T Data;
    }
}
