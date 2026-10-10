using System;
using System.Collections;
using System.Text;
using Griot.VR.Authentication;
using Newtonsoft.Json;
using UnityEngine;
using UnityEngine.Networking;

namespace Griot.VR.Network
{
    /// <summary>
    /// The one type in this project that touches the network. Coroutines
    /// GET, POST and PATCH against the Django VR API and hand every
    /// outcome back as an <see cref="ApiResult"/> — success, HTTP error,
    /// timeout, unreachable host, unreadable body — so callers render one
    /// error path instead of catching exceptions.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Scene and UI scripts never call these methods directly; they go
    /// through <see cref="GriotVrBootstrap"/> (see the project README). The
    /// bearer token is read from <see cref="VRTokenStore"/> at send time
    /// and is never logged, stored or passed in a URL.
    /// </para>
    /// <para>
    /// Mock mode short-circuits each high-level call with the stub
    /// payloads from <see cref="MockApi"/> — same parsing, same result
    /// shapes, no sockets — so the pipeline around the network keeps being
    /// exercised during development.
    /// </para>
    /// </remarks>
    public sealed class GriotApiClient
    {
        /// <summary>Client-side error code: the request outlived its timeout.</summary>
        public const string ErrorCodeTimeout = "timeout";

        /// <summary>Client-side error code: DNS, TLS or connection failed.</summary>
        public const string ErrorCodeNetwork = "network_unavailable";

        /// <summary>Client-side error code: the body was not the JSON we expect.</summary>
        public const string ErrorCodeInvalidResponse = "invalid_response";

        const string LogPrefix = "[GriotVR] ";
        const int MaxDeviceModelLength = 120;

        readonly string baseUrl;
        readonly int timeoutSeconds;
        readonly bool useMock;
        readonly VRTokenStore tokenStore;

        public GriotApiClient(GriotApiConfig config, VRTokenStore tokens)
        {
            var resolved = config != null ? config : GriotApiConfig.CreateRuntimeDefault();
            baseUrl = resolved.BaseUrl;
            timeoutSeconds = resolved.RequestTimeoutSeconds;
            useMock = resolved.UseMockApi;
            tokenStore = tokens;
        }

        /// <summary>True when this client answers from <see cref="MockApi"/>.</summary>
        public bool UsesMockApi => useMock;

        // ---- high-level calls ------------------------------------------------

        /// <summary>
        /// <c>POST /api/vr/launch/exchange/</c> — burn the single-use launch
        /// token and open a VR session. The caller stores the returned
        /// access token; this method only reports the outcome.
        /// </summary>
        public IEnumerator ExchangeLaunch(
            string launchToken,
            string deviceModel,
            Action<ApiResult<LaunchExchangeResponse>> done)
        {
            if (deviceModel != null && deviceModel.Length > MaxDeviceModelLength)
            {
                deviceModel = deviceModel.Substring(0, MaxDeviceModelLength);
            }

            if (useMock)
            {
                yield return null;
                done(MockResult<LaunchExchangeResponse>(
                    MockApi.ExchangeResponseJson(), "vr/launch/exchange/"));
                yield break;
            }

            var body = JsonConvert.SerializeObject(
                new LaunchExchangeRequest(launchToken, deviceModel));

            ApiResult raw = null;
            yield return Post("vr/launch/exchange/", body, r => raw = r);
            done(Deserialize<LaunchExchangeResponse>(raw));
        }

        /// <summary>
        /// <c>GET /api/vr/experiences/{key}/</c> — the scene manifest by id
        /// or slug. Requires the session token from a completed exchange.
        /// </summary>
        public IEnumerator GetExperience(string key, Action<ApiResult<ExperiencePayload>> done)
        {
            var path = "vr/experiences/" + UnityWebRequest.EscapeURL(key ?? string.Empty) + "/";

            if (useMock)
            {
                yield return null;
                done(MockResult<ExperiencePayload>(MockApi.ExperienceJson(), path));
                yield break;
            }

            ApiResult raw = null;
            yield return Get(path, r => raw = r);
            done(Deserialize<ExperiencePayload>(raw));
        }

        /// <summary>
        /// <c>PATCH /api/vr/progress/</c> — record how far the reader has
        /// got. The session comes from the token's <c>sid</c> claim, never
        /// from this body, so the headset cannot progress anyone else's
        /// visit. Omitting <paramref name="progress"/> records only the
        /// viewed-artifact list.
        /// </summary>
        public IEnumerator RecordProgress(
            float? progress,
            int[] artifactsViewed,
            Action<ApiResult> done)
        {
            if (useMock)
            {
                yield return null;
                done(new ApiResult { Ok = true, StatusCode = 200 });
                yield break;
            }

            var body = JsonConvert.SerializeObject(
                new ProgressUpdateRequest(progress, artifactsViewed));
            yield return Patch("vr/progress/", body, done);
        }

        // ---- transport -------------------------------------------------------

        public IEnumerator Get(string path, Action<ApiResult> done)
        {
            yield return Send(UnityWebRequest.kHttpVerbGET, path, null, done);
        }

        public IEnumerator Post(string path, string jsonBody, Action<ApiResult> done)
        {
            yield return Send(UnityWebRequest.kHttpVerbPOST, path, jsonBody, done);
        }

        public IEnumerator Patch(string path, string jsonBody, Action<ApiResult> done)
        {
            yield return Send("PATCH", path, jsonBody, done);
        }

        IEnumerator Send(string method, string path, string jsonBody, Action<ApiResult> done)
        {
            var url = baseUrl + "/" + path.TrimStart('/');

            // `using` is try/finally, which iterators permit around a yield;
            // the request is disposed either way, including on timeout.
            using (var request = new UnityWebRequest(url, method))
            {
                if (jsonBody != null)
                {
                    var upload = new UploadHandlerRaw(Encoding.UTF8.GetBytes(jsonBody));
                    upload.contentType = "application/json";
                    request.uploadHandler = upload;
                }

                request.downloadHandler = new DownloadHandlerBuffer();
                request.SetRequestHeader("Accept", "application/json");

                var token = tokenStore != null ? tokenStore.AccessToken() : null;
                if (!string.IsNullOrEmpty(token))
                {
                    request.SetRequestHeader("Authorization", "Bearer " + token);
                }

                request.timeout = timeoutSeconds;

                yield return request.SendWebRequest();

                var result = Classify(request, method, path);
                if (result.Ok)
                {
                    Debug.Log(LogPrefix + method + " " + path + " → " + result.StatusCode + ".");
                }
                else
                {
                    Debug.LogWarning(
                        LogPrefix + method + " " + path + " → " +
                        (result.StatusCode != 0 ? result.StatusCode.ToString() : "no response") +
                        " (" + result.ErrorCode + "): " + result.Message);
                }

                done(result);
            }
        }

        /// <summary>
        /// Turn a finished request into an <see cref="ApiResult"/>. Order
        /// matters: a timeout and an HTTP 500 both arrive as failures but
        /// need different copy, so transport problems are classified before
        /// status codes are read.
        /// </summary>
        static ApiResult Classify(UnityWebRequest request, string method, string path)
        {
            var status = request.responseCode;
            var body = request.downloadHandler != null ? request.downloadHandler.text : null;

            if (request.result == UnityWebRequest.Result.ConnectionError)
            {
                var error = request.error ?? string.Empty;
                var timedOut =
                    error.IndexOf("timeout", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    error.IndexOf("timed out", StringComparison.OrdinalIgnoreCase) >= 0;

                return new ApiResult
                {
                    StatusCode = status,
                    ErrorCode = timedOut ? ErrorCodeTimeout : ErrorCodeNetwork,
                    Message = timedOut
                        ? "The request timed out after " + request.timeout + "s: " + error
                        : "The server could not be reached: " + error,
                    Body = body,
                };
            }

            if (request.result == UnityWebRequest.Result.ProtocolError)
            {
                // A Django error body: {"error": "...", "code": "..."}.
                var parsed = TryParseError(body);
                var hasCode = parsed != null && !string.IsNullOrEmpty(parsed.Code);
                return new ApiResult
                {
                    StatusCode = status,
                    ErrorCode = hasCode ? parsed.Code : "http_" + status,
                    Message = parsed != null && !string.IsNullOrEmpty(parsed.Error)
                        ? parsed.Error
                        : "HTTP " + status + ".",
                    Body = body,
                };
            }

            if (request.result != UnityWebRequest.Result.Success)
            {
                return new ApiResult
                {
                    StatusCode = status,
                    ErrorCode = ErrorCodeInvalidResponse,
                    Message = "The response could not be processed: " +
                              (request.error ?? "unknown error"),
                    Body = body,
                };
            }

            return new ApiResult { Ok = true, StatusCode = status, Body = body };
        }

        static ApiErrorBody TryParseError(string body)
        {
            if (string.IsNullOrEmpty(body)) return null;
            try
            {
                return JsonConvert.DeserializeObject<ApiErrorBody>(body);
            }
            catch (JsonException)
            {
                return null;
            }
        }

        static ApiResult<T> Deserialize<T>(ApiResult raw)
        {
            var result = new ApiResult<T>
            {
                Ok = raw.Ok,
                StatusCode = raw.StatusCode,
                ErrorCode = raw.ErrorCode,
                Message = raw.Message,
                Body = raw.Body,
            };

            if (!raw.Ok) return result;

            try
            {
                result.Data = JsonConvert.DeserializeObject<T>(raw.Body);
            }
            catch (JsonException ex)
            {
                result.Ok = false;
                result.ErrorCode = ErrorCodeInvalidResponse;
                result.Message = "The response body was not readable JSON: " + ex.Message;
                return result;
            }

            if (result.Data == null)
            {
                result.Ok = false;
                result.ErrorCode = ErrorCodeInvalidResponse;
                result.Message = "The server returned an empty response.";
            }

            return result;
        }

        static ApiResult<T> MockResult<T>(string json, string path)
        {
            Debug.Log(LogPrefix + "Mock API served " + path + ".");
            return Deserialize<T>(new ApiResult { Ok = true, StatusCode = 200, Body = json });
        }
    }
}
