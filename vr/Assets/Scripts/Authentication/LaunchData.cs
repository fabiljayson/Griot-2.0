using System;
using System.Collections.Generic;
using System.Globalization;

namespace Griot.VR.Authentication
{
    /// <summary>
    /// A parsed <c>griotvr://launch</c> link.
    /// </summary>
    /// <remarks>
    /// A deep link is attacker-supplied: any app on the device can register the
    /// scheme, so this type's job is to be strict about what it will accept and
    /// to hold nothing but an opaque token and two ids. Nothing here is trusted
    /// — the token is worthless until Django validates it — and the parse fails
    /// closed on anything unexpected rather than passing a half-understood URL
    /// deeper into the app.
    /// </remarks>
    [Serializable]
    public sealed class LaunchData
    {
        public const string Scheme = "griotvr";
        public const string Host = "launch";

        /// <summary>Shortest token accepted. Matches the Flutter client.</summary>
        public const int MinTokenLength = 16;

        /// <summary>Longest token accepted. Matches the API's field limit.</summary>
        public const int MaxTokenLength = 200;

        public string Token { get; private set; }
        public int ExperienceId { get; private set; }
        public int? ArtifactId { get; private set; }

        private LaunchData(string token, int experienceId, int? artifactId)
        {
            Token = token;
            ExperienceId = experienceId;
            ArtifactId = artifactId;
        }

        /// <summary>
        /// Parse <paramref name="url"/>, returning false with a reason when it
        /// is not a launch link this app can act on.
        /// </summary>
        public static bool TryParse(string url, out LaunchData data, out string error)
        {
            data = null;

            if (string.IsNullOrWhiteSpace(url))
            {
                error = "No launch link was received.";
                return false;
            }

            Uri uri;
            if (!Uri.TryCreate(url, UriKind.Absolute, out uri))
            {
                error = "The launch link could not be read.";
                return false;
            }

            if (!string.Equals(uri.Scheme, Scheme, StringComparison.OrdinalIgnoreCase))
            {
                error = "The launch link uses an unexpected scheme.";
                return false;
            }

            if (!string.Equals(uri.Host, Host, StringComparison.OrdinalIgnoreCase))
            {
                error = "The launch link points somewhere unexpected.";
                return false;
            }

            var query = ParseQuery(uri.Query);

            string token;
            if (!query.TryGetValue("token", out token) || !IsPlausibleToken(token))
            {
                error = "The launch link has no usable token.";
                return false;
            }

            int experienceId;
            if (!TryParseId(query, "experience", out experienceId))
            {
                error = "The launch link has no usable experience id.";
                return false;
            }

            int? artifactId = null;
            string rawArtifact;
            if (query.TryGetValue("artifact", out rawArtifact) && !string.IsNullOrEmpty(rawArtifact))
            {
                int parsed;
                if (!int.TryParse(rawArtifact, NumberStyles.Integer, CultureInfo.InvariantCulture, out parsed)
                    || parsed <= 0)
                {
                    // A malformed artifact id is refused rather than ignored:
                    // silently dropping it would open the experience without
                    // highlighting what the reader just tapped, and the reader
                    // would have no way to tell that from a normal launch.
                    error = "The launch link has an unusable artifact id.";
                    return false;
                }

                artifactId = parsed;
            }

            error = null;
            data = new LaunchData(token, experienceId, artifactId);
            return true;
        }

        /// <summary>
        /// True when <paramref name="token"/> is shaped like a token this
        /// platform mints: URL-safe base64, of a sane length.
        /// </summary>
        public static bool IsPlausibleToken(string token)
        {
            if (string.IsNullOrEmpty(token)) return false;
            if (token.Length < MinTokenLength || token.Length > MaxTokenLength) return false;

            for (var i = 0; i < token.Length; i++)
            {
                var c = token[i];
                var isUrlSafe =
                    (c >= 'A' && c <= 'Z') ||
                    (c >= 'a' && c <= 'z') ||
                    (c >= '0' && c <= '9') ||
                    c == '-' || c == '_';

                if (!isUrlSafe) return false;
            }

            return true;
        }

        private static bool TryParseId(IDictionary<string, string> query, string key, out int value)
        {
            value = 0;
            string raw;
            if (!query.TryGetValue(key, out raw) || string.IsNullOrEmpty(raw)) return false;
            return int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out value)
                   && value > 0;
        }

        /// <summary>
        /// Parse a query string without <c>System.Web</c>, which is not present
        /// in an IL2CPP Android build.
        /// </summary>
        private static IDictionary<string, string> ParseQuery(string query)
        {
            var result = new Dictionary<string, string>(StringComparer.Ordinal);
            if (string.IsNullOrEmpty(query)) return result;

            var trimmed = query[0] == '?' ? query.Substring(1) : query;
            var pairs = trimmed.Split('&');

            foreach (var pair in pairs)
            {
                if (pair.Length == 0) continue;

                var separator = pair.IndexOf('=');
                string key;
                string value;

                if (separator < 0)
                {
                    key = pair;
                    value = string.Empty;
                }
                else
                {
                    key = pair.Substring(0, separator);
                    value = pair.Substring(separator + 1);
                }

                key = Uri.UnescapeDataString(key);
                value = Uri.UnescapeDataString(value);

                // First value wins. Duplicated parameters are what a forged link
                // looks like, and picking "the last one" or "the first one"
                // differently in two places is how a parser-confusion bug starts.
                if (!result.ContainsKey(key)) result[key] = value;
            }

            return result;
        }

        public override string ToString()
        {
            return string.Format(
                CultureInfo.InvariantCulture,
                "LaunchData(experience={0}, artifact={1}, token=***)",
                ExperienceId,
                ArtifactId.HasValue ? ArtifactId.Value.ToString(CultureInfo.InvariantCulture) : "none");
        }
    }
}
