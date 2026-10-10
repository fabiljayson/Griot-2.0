using System;
using System.Collections;
using Griot.VR.Authentication;
using UnityEngine;

namespace Griot.VR.Network
{
    /// <summary>
    /// Owns the launch handoff: exchanges the single-use deep-link token
    /// for a VR session through <see cref="GriotApiClient"/>, keeps the
    /// resulting JWT in <see cref="VRTokenStore"/>, and turns every failure
    /// code — from Django or from the transport — into copy written for a
    /// person wearing a headset.
    /// </summary>
    /// <remarks>
    /// Nothing here is a MonoBehaviour: it is driven by coroutines started
    /// by <see cref="GriotVrBootstrap"/>, which is also the only thing that
    /// renders the failures this type reports. The token is stored, never
    /// logged — see <see cref="VRTokenStore"/> for why it is memory-only.
    /// </remarks>
    public sealed class AuthManager
    {
        /// <summary>Client-side error code: the app was opened without a link.</summary>
        public const string ErrorCodeMissingLaunch = "missing_launch";

        /// <summary>Result of one exchange attempt, success or failure.</summary>
        public sealed class Result
        {
            /// <summary>True when a session token is stored and usable.</summary>
            public bool Ok;

            /// <summary>Machine code on failure; null on success.</summary>
            public string ErrorCode;

            /// <summary>Headset-readable reason on failure; null on success.</summary>
            public string UserMessage;

            /// <summary>The exchange response on success — session token and payload.</summary>
            public LaunchExchangeResponse Exchange;
        }

        readonly GriotApiClient client;
        readonly VRTokenStore tokenStore;

        public AuthManager(GriotApiClient apiClient, VRTokenStore tokens)
        {
            client = apiClient;
            tokenStore = tokens != null ? tokens : new VRTokenStore();
        }

        /// <summary>The store the API client reads its Authorization header from.</summary>
        public VRTokenStore TokenStore => tokenStore;

        /// <summary>True while a usable session token is held.</summary>
        public bool HasSession => tokenStore.HasUsableToken;

        /// <summary>
        /// Exchange a parsed launch link for a session. On success the
        /// access token is stored and <see cref="Result.Exchange"/> carries
        /// the full experience payload; on failure <see cref="Result.ErrorCode"/>
        /// is the raw machine code and <see cref="Result.UserMessage"/> is
        /// what the reader should be told.
        /// </summary>
        public IEnumerator Exchange(LaunchData launch, Action<Result> done)
        {
            if (launch == null)
            {
                done(Failure(ErrorCodeMissingLaunch));
                yield break;
            }

            ApiResult<LaunchExchangeResponse> raw = null;
            yield return client.ExchangeLaunch(
                launch.Token, SystemInfo.deviceModel, r => raw = r);

            if (raw.Ok &&
                raw.Data != null &&
                !string.IsNullOrEmpty(raw.Data.AccessToken) &&
                raw.Data.Experience != null)
            {
                tokenStore.Store(raw.Data.AccessToken, raw.Data.ExpiresIn);
                done(new Result { Ok = true, Exchange = raw.Data });
                yield break;
            }

            var code = string.IsNullOrEmpty(raw.ErrorCode) ? "unknown" : raw.ErrorCode;
            Debug.LogError(
                "[GriotVR] Launch exchange failed (" + code + "): " + raw.Message);
            done(Failure(code));
        }

        /// <summary>Forget the session token. Session completion, or an error.</summary>
        public void SignOut()
        {
            tokenStore.Clear();
        }

        /// <summary>
        /// Copy for a person wearing a headset, keyed by the machine codes
        /// Django and the transport actually produce. Every line tells the
        /// reader what to do next, not what the protocol did wrong.
        /// </summary>
        public static string UserMessageFor(string errorCode)
        {
            switch (errorCode)
            {
                case "invalid_token":
                    return "This launch link is not valid. Close this app and open the experience again from the Griot app.";

                case "token_expired":
                    return "This launch link has expired. Open the experience again from the Griot app to start a new visit.";

                case "token_used":
                    return "This launch link has already been used. Open the experience again from the Griot app to get a fresh one.";

                case "experience_unavailable":
                case "no_vr_experience":
                case "experience_not_found":
                case "http_404":
                    return "This experience is not available right now. Try again later from the Griot app.";

                case "http_401":
                case "http_403":
                    return "This visit is no longer authorised. Open the experience again from the Griot app to start a new one.";

                case GriotApiClient.ErrorCodeTimeout:
                    return "The Griot server took too long to answer. Check the headset's Wi-Fi and launch the experience again.";

                case GriotApiClient.ErrorCodeNetwork:
                    return "The Griot server could not be reached. Check the headset's Wi-Fi and launch the experience again.";

                case GriotApiClient.ErrorCodeInvalidResponse:
                    return "The Griot server sent something this app could not read. Please try again later.";

                case ErrorCodeMissingLaunch:
                    return "This app was opened without a launch link. Open the experience from the Griot app instead.";

                default:
                    return "The experience could not be opened. Launch it again from the Griot app.";
            }
        }

        static Result Failure(string errorCode)
        {
            return new Result
            {
                Ok = false,
                ErrorCode = errorCode,
                UserMessage = UserMessageFor(errorCode),
            };
        }
    }
}
