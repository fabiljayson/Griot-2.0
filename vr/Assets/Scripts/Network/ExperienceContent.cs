using System;
using System.Collections.Generic;
using UnityEngine;

namespace Griot.VR.Network
{
    /// <summary>
    /// The experience payload currently in play, plus the merge rules that
    /// turn one payload artifact into the scene's <see cref="ArtifactData"/>.
    /// </summary>
    /// <remarks>
    /// <para>
    /// This is a content hub, not a network type: <c>ArtifactSpawner</c>
    /// reads from it in <c>Start</c>, and it reports viewed artifacts
    /// upward through <see cref="ArtifactViewed"/> so scene code never
    /// builds a request itself. <see cref="GriotVrBootstrap"/> owns the
    /// <see cref="GriotApiClient"/> that fulfils those requests.
    /// </para>
    /// <para>
    /// Merge rule: the backend wins whenever it sends a non-empty value;
    /// anything blank — a field an older backend omits, or a column the
    /// curator left empty — keeps the scene's local, sourced copy. So a
    /// payload that lacks <c>historical_significance</c> degrades to the
    /// local text instead of blanking the Learn More panel.
    /// </para>
    /// </remarks>
    public static class ExperienceContent
    {
        static readonly HashSet<int> ViewedIds = new HashSet<int>();

        /// <summary>The payload the scene is built from, or null when local data only.</summary>
        public static ExperiencePayload Current { get; private set; }

        /// <summary>Raised once per artifact the reader opens, with its Django id.</summary>
        public static event Action<int> ArtifactViewed;

        /// <summary>Install a payload (fresh from exchange or from GET experiences).</summary>
        public static void Set(ExperiencePayload payload)
        {
            Current = payload;
            ViewedIds.Clear();
        }

        /// <summary>Drop the payload and the viewed list — back to scene-local data.</summary>
        public static void Clear()
        {
            Current = null;
            ViewedIds.Clear();
        }

        /// <summary>Find an artifact in the current payload by slug or id, else null.</summary>
        public static PlacedArtifact FindArtifact(string key)
        {
            return Current != null ? Current.FindArtifact(key) : null;
        }

        /// <summary>
        /// Record that the reader opened an artifact. Fires
        /// <see cref="ArtifactViewed"/> only the first time, so the
        /// progress PATCH carries the cumulative list without repeating a
        /// request per glance.
        /// </summary>
        public static void ReportViewed(string key)
        {
            var artifact = FindArtifact(key);
            if (artifact == null) return;
            if (!ViewedIds.Add(artifact.Id)) return;

            var handler = ArtifactViewed;
            if (handler != null) handler(artifact.Id);
        }

        /// <summary>Every artifact id viewed so far — what PATCH progress sends.</summary>
        public static int[] ViewedArtifactIds()
        {
            var ids = new int[ViewedIds.Count];
            ViewedIds.CopyTo(ids);
            return ids;
        }

        /// <summary>
        /// Merge one payload artifact into the scene's local data: backend
        /// text wins when present, blank fields keep the local value.
        /// The result is a new instance — the serialized scene data on the
        /// spawner stays untouched for the next run.
        /// </summary>
        public static ArtifactData ToArtifactData(PlacedArtifact remote, ArtifactData local)
        {
            if (local == null) local = new ArtifactData();
            if (remote == null) return local;

            // A source URL from Django replaces the scene's provenance
            // label; without one the local label stands as it was.
            var sourceLabel = string.IsNullOrEmpty(remote.SourceUrl)
                ? local.sourceLabel
                : remote.SourceUrl;

            return new ArtifactData
            {
                artifactId = FirstNonEmpty(remote.Slug, local.artifactId),
                title = FirstNonEmpty(remote.Name, local.title),
                description = FirstNonEmpty(remote.Description, local.description),
                historicalSignificance = FirstNonEmpty(
                    remote.HistoricalSignificance, local.historicalSignificance),
                culture = FirstNonEmpty(remote.Culture, local.culture),
                region = FirstNonEmpty(remote.Region, local.region),
                materials = FirstNonEmpty(remote.Materials, local.materials),
                sourceUrl = FirstNonEmpty(remote.SourceUrl, local.sourceUrl),
                sourceLabel = sourceLabel,
            };
        }

        static string FirstNonEmpty(string preferred, string fallback)
        {
            return string.IsNullOrEmpty(preferred) ? fallback : preferred;
        }

        // Clears static state when Enter Play Mode disables domain reload,
        // otherwise a payload from the previous play survives the next one.
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetStatics()
        {
            Current = null;
            ArtifactViewed = null;
            ViewedIds.Clear();
        }
    }
}
