using System;

namespace Griot.VR.Authentication
{
    /// <summary>
    /// The single funnel for every <c>griotvr://launch</c> the app receives:
    /// cold start via <c>Application.absoluteURL</c> and warm starts via
    /// <c>Application.deepLinkActivated</c> both end here.
    /// </summary>
    /// <remarks>
    /// Parsing is not validation. A link that reaches <see cref="LaunchReceived"/>
    /// still carries nothing but an opaque token — Django decides whether that
    /// token is worth anything when Unity exchanges it (Milestone 6). Nothing in
    /// this type logs the URL, because the URL carries the token.
    /// </remarks>
    public static class DeepLinkManager
    {
        /// <summary>
        /// Raised when a launch link parses. The contained token has not been
        /// verified against the backend at this point.
        /// </summary>
        public static event Action<LaunchData> LaunchReceived;

        /// <summary>
        /// Raised with a human-readable reason when a link this app owns
        /// (<c>griotvr://</c>) cannot be used.
        /// </summary>
        public static event Action<string> LaunchRejected;

        /// <summary>The most recent link that parsed, or null.</summary>
        public static LaunchData LastLaunch { get; private set; }

        public static bool TryHandle(string url, out LaunchData data, out string error)
        {
            if (!LaunchData.TryParse(url, out data, out error))
            {
                var handler = LaunchRejected;
                if (handler != null) handler(error);
                return false;
            }

            LastLaunch = data;

            var received = LaunchReceived;
            if (received != null) received(data);

            return true;
        }
    }
}
