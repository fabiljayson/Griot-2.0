using System;

namespace Griot.VR.Authentication
{
    /// <summary>
    /// Holds the VR session token for as long as the app is running.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Memory only, on purpose. <c>PlayerPrefs</c> is an unencrypted XML file in
    /// the app's data directory — on a sideloaded Quest build that is readable
    /// by anyone with the device, and it survives the app being closed. A token
    /// written there outlives the visit it was minted for, and the whole design
    /// of the launch handoff is that VR access is short and bounded.
    /// </para>
    /// <para>
    /// The token is never logged either. There is no <c>ToString</c> that
    /// reveals it, and the only method that returns it is the one the API
    /// client calls to build an Authorization header.
    /// </para>
    /// </remarks>
    public sealed class VRTokenStore
    {
        private string _token;
        private DateTimeOffset _expiresAt = DateTimeOffset.MinValue;

        /// <summary>How long before expiry a token is treated as spent.</summary>
        private static readonly TimeSpan RefreshMargin = TimeSpan.FromSeconds(60);

        /// <summary>True when there is a token with useful time left on it.</summary>
        public bool HasUsableToken
        {
            get
            {
                if (string.IsNullOrEmpty(_token)) return false;
                return DateTimeOffset.UtcNow + RefreshMargin < _expiresAt;
            }
        }

        public DateTimeOffset ExpiresAt
        {
            get { return _expiresAt; }
        }

        /// <summary>
        /// Store a freshly exchanged token.
        /// </summary>
        /// <param name="token">The access token from the API.</param>
        /// <param name="lifetimeSeconds">Its reported lifetime in seconds.</param>
        public void Store(string token, int lifetimeSeconds)
        {
            if (string.IsNullOrEmpty(token))
            {
                throw new ArgumentException("A VR session token must not be empty.", nameof(token));
            }

            _token = token;
            _expiresAt = DateTimeOffset.UtcNow.AddSeconds(Math.Max(1, lifetimeSeconds));
        }

        /// <summary>The bearer token, or null when there is none to send.</summary>
        public string AccessToken()
        {
            return string.IsNullOrEmpty(_token) ? null : _token;
        }

        /// <summary>Forget the token. Called on session completion and on error.</summary>
        public void Clear()
        {
            _token = null;
            _expiresAt = DateTimeOffset.MinValue;
        }
    }
}
