#!/usr/bin/env python3
"""Generate a OneTabTube stub for BrowserMediaRouter as a srcjar."""

import argparse
import textwrap
import zipfile


def _stub_sources():
    return {
        "org/chromium/components/media_router/BrowserMediaRouter.java": textwrap.dedent(
            """\
            package org.chromium.components.media_router;

            import androidx.mediarouter.media.MediaRouter;

            import org.jni_zero.NativeMethods;

            import org.chromium.base.ContextUtils;
            import org.chromium.build.annotations.NullMarked;
            import org.chromium.build.annotations.Nullable;
            import org.chromium.content_public.browser.WebContents;

            import java.util.ArrayList;
            import java.util.HashMap;
            import java.util.List;
            import java.util.Map;

            @NullMarked
            public class BrowserMediaRouter implements MediaRouteManager {
                private final List<MediaRouteProvider> mRouteProviders = new ArrayList<>();
                private final Map<String, MediaRouteProvider> mRouteIdsToProviders = new HashMap<>();
                private final Map<String, Map<MediaRouteProvider, List<MediaSink>>>
                        mSinksPerSourcePerProvider = new HashMap<>();
                private final Map<String, List<MediaSink>> mSinksPerSource = new HashMap<>();

                public static void setRouteProviderFactoryForTest(MediaRouteProvider.Factory factory) {}

                protected List<MediaRouteProvider> getRouteProvidersForTest() {
                    return mRouteProviders;
                }

                protected Map<String, MediaRouteProvider> getRouteIdsToProvidersForTest() {
                    return mRouteIdsToProviders;
                }

                protected Map<String, Map<MediaRouteProvider, List<MediaSink>>>
                        getSinksPerSourcePerProviderForTest() {
                    return mSinksPerSourcePerProvider;
                }

                protected Map<String, List<MediaSink>> getSinksPerSourceForTest() {
                    return mSinksPerSource;
                }

                public static MediaRouter getAndroidMediaRouter() {
                    return MediaRouter.getInstance(ContextUtils.getApplicationContext());
                }

                @Override
                public void addMediaRouteProvider(MediaRouteProvider provider) {
                    mRouteProviders.add(provider);
                }

                @Override
                public void onSinksReceived(
                        String sourceId, MediaRouteProvider provider, List<MediaSink> sinks) {}

                @Override
                public void onRouteCreated(
                        String mediaRouteId,
                        String mediaSinkId,
                        int requestId,
                        MediaRouteProvider provider,
                        boolean wasLaunched) {}

                @Override
                public void onCreateRouteRequestError(String errorText, int requestId) {}

                @Override
                public void onJoinRouteRequestError(String errorText, int requestId) {}

                @Override
                public void onRouteTerminated(String mediaRouteId) {}

                @Override
                public void onRouteClosed(String mediaRouteId, @Nullable String error) {}

                @Override
                public void onMessage(String mediaRouteId, String message) {}

                @Override
                public void onRouteMediaSourceUpdated(String mediaRouteId, String mediaSourceId) {}

                public static BrowserMediaRouter create(long nativeMediaRouterAndroidBridge) {
                    return new BrowserMediaRouter(nativeMediaRouterAndroidBridge);
                }

                public boolean startObservingMediaSinks(String sourceId) {
                    return false;
                }

                public void stopObservingMediaSinks(String sourceId) {}

                public @Nullable String getSinkUrn(String sourceUrn, int index) {
                    return null;
                }

                public @Nullable String getSinkName(String sourceUrn, int index) {
                    return null;
                }

                public void createRoute(
                        String sourceId,
                        String sinkId,
                        String presentationId,
                        String origin,
                        int tabId,
                        boolean isOffTheRecord,
                        int nativeRequestId) {}

                public void joinRoute(
                        String sourceId,
                        String presentationId,
                        String origin,
                        int tabId,
                        int nativeRequestId,
                        WebContents webContents) {}

                public void closeRoute(String routeId) {}

                public void detachRoute(String routeId) {}

                public void sendStringMessage(String routeId, String message) {}

                public @Nullable FlingingControllerBridge getFlingingControllerBridge(
                        String routeId) {
                    return null;
                }

                protected BrowserMediaRouter(long nativeMediaRouterAndroidBridge) {}

                public void teardown() {}

                @NativeMethods
                interface Natives {
                    void onSinksReceived(
                            long nativeMediaRouterAndroidBridge, String sourceUrn, int count);

                    void onRouteCreated(
                            long nativeMediaRouterAndroidBridge,
                            String mediaRouteId,
                            String mediaSinkId,
                            int createRouteRequestId,
                            boolean wasLaunched);

                    void onCreateRouteRequestError(
                            long nativeMediaRouterAndroidBridge,
                            String errorText,
                            int requestId);

                    void onJoinRouteRequestError(
                            long nativeMediaRouterAndroidBridge,
                            String errorText,
                            int requestId);

                    void onRouteTerminated(
                            long nativeMediaRouterAndroidBridge, String mediaRouteId);

                    void onRouteClosed(
                            long nativeMediaRouterAndroidBridge,
                            String mediaRouteId,
                            @Nullable String message);

                    void onMessage(
                            long nativeMediaRouterAndroidBridge,
                            String mediaRouteId,
                            String message);

                    void onRouteMediaSourceUpdated(
                            long nativeMediaRouterAndroidBridge,
                            String mediaRouteId,
                            String mediaSourceId);
                }
            }
            """
        ),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-srcjar", required=True)
    args = parser.parse_args()

    with zipfile.ZipFile(args.output_srcjar, "w", zipfile.ZIP_DEFLATED) as out:
        for path, contents in _stub_sources().items():
            out.writestr(path, contents)


if __name__ == "__main__":
    main()
