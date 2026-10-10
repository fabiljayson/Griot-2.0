namespace Griot.VR.Network
{
    /// <summary>
    /// Hand-written payloads served when mock mode is on — an offline stub
    /// for developing the Unity ↔ Django pipeline without a backend.
    /// </summary>
    /// <remarks>
    /// The stub content is explicitly labelled as mock content and never
    /// invents cultural facts: text that looks real in a dev build is text
    /// someone forgets to replace in a release build. The artifact slug
    /// matches the scene's <c>ArtifactSpawner</c> so the merge path —
    /// payload over local data — is what a developer actually sees working.
    /// </remarks>
    public static class MockApi
    {
        /// <summary>Same shape as <c>POST /api/vr/launch/exchange/</c>.</summary>
        public static string ExchangeResponseJson()
        {
            return @"{
                ""access_token"": ""mock-session-token-not-a-real-credential"",
                ""expires_in"": 110,
                ""session"": {
                    ""id"": 1,
                    ""completion_status"": ""active"",
                    ""progress"": 0.0
                },
                ""experience"":" + ExperienceJson() + @"
            }";
        }

        /// <summary>Same shape as <c>GET /api/vr/experiences/{key}/</c>.</summary>
        public static string ExperienceJson()
        {
            return @"{
                ""id"": 1,
                ""slug"": ""cameroon-heritage-museum"",
                ""title"": ""Cameroon Heritage Museum (Mock)"",
                ""description"": ""Mock experience served by GriotVR's offline API stub."",
                ""scene_identifier"": ""CameroonHeritageMuseum"",
                ""thumbnail"": null,
                ""language"": ""en"",
                ""environment"": ""cameroon_heritage_museum"",
                ""museum_name"": ""Mock Gallery"",
                ""region"": ""Development"",
                ""culture"": ""Local mock data"",
                ""updated_at"": ""2026-01-01T00:00:00+00:00"",
                ""artifact_count"": 1,
                ""artifacts"": [
                    {
                        ""id"": 1,
                        ""slug"": ""ndop-textile"",
                        ""name"": ""Ndop Textile (Mock)"",
                        ""description"": ""MOCK DATA — served by the in-headset API stub while mock mode is on. This text was written by MockApi.cs to prove the payload reached Unity; it did not come from Django."",
                        ""category"": ""textile"",
                        ""content_type"": ""textile"",
                        ""culture"": """",
                        ""region"": """",
                        ""estimated_date"": """",
                        ""materials"": """",
                        ""dimensions"": """",
                        ""image"": null,
                        ""museum_name"": ""Mock Gallery"",
                        ""floor"": """",
                        ""display_case"": """",
                        ""historical_significance"": """",
                        ""source_url"": """",
                        ""stories"": [],
                        ""order"": 0,
                        ""model_url"": null,
                        ""model_scale"": 1.0,
                        ""is_interactive"": true,
                        ""narration"": null
                    }
                ]
            }";
        }
    }
}
