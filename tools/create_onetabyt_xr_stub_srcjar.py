#!/usr/bin/env python3
"""Generate a OneTabTube XR stub srcjar."""

import argparse
import textwrap
import zipfile


def _stub_sources():
    return {
        "org/chromium/chrome/browser/xr/scenecore/XrModuleProvider.java": textwrap.dedent(
            """\
            package org.chromium.chrome.browser.xr.scenecore;

            import android.app.Activity;

            import org.chromium.build.annotations.NullMarked;
            import org.chromium.chrome.browser.lifecycle.ActivityLifecycleDispatcher;
            import org.chromium.ui.xr.scenecore.XrSceneCoreSessionInitializer;
            import org.chromium.ui.xr.scenecore.XrSceneCoreSessionManager;

            @NullMarked
            public interface XrModuleProvider {
                XrSceneCoreSessionManager getXrSceneCoreSessionManager(Activity activity);

                XrSceneCoreSessionInitializer getXrSceneCoreSessionInitializer(
                        ActivityLifecycleDispatcher dispatcher,
                        XrSceneCoreSessionManager manager);
            }
            """
        ),
        "org/chromium/chrome/browser/xr/scenecore/XrModule.java": textwrap.dedent(
            """\
            package org.chromium.chrome.browser.xr.scenecore;

            import org.chromium.base.supplier.NonNullObservableSupplier;
            import org.chromium.base.supplier.ObservableSuppliers;
            import org.chromium.build.annotations.NullMarked;
            import org.chromium.ui.xr.scenecore.XrSceneCoreSessionInitializer;
            import org.chromium.ui.xr.scenecore.XrSceneCoreSessionManager;

            @NullMarked
            public final class XrModule {
                public static final String SPLIT_NAME = "xr";

                private static final XrSceneCoreSessionInitializer NO_OP_INITIALIZER =
                        new XrSceneCoreSessionInitializer() {
                            @Override
                            public void initialize(boolean isFullSpaceMode) {}

                            @Override
                            public void destroy() {}
                        };

                private static final XrSceneCoreSessionManager NO_OP_MANAGER =
                        new XrSceneCoreSessionManager() {
                            @Override
                            public boolean requestSpaceModeChange(boolean requestFullSpaceMode) {
                                return false;
                            }

                            @Override
                            public boolean requestSpaceModeChange(
                                    boolean requestFullSpaceMode, Runnable completedCallback) {
                                return false;
                            }

                            @Override
                            public NonNullObservableSupplier<Boolean>
                                    getXrSpaceModeObservableSupplier() {
                                return ObservableSuppliers.alwaysFalse();
                            }

                            @Override
                            public boolean isXrFullSpaceMode() {
                                return false;
                            }

                            @Override
                            public void setMainPanelVisibility(boolean visible) {}

                            @Override
                            public void destroy() {}
                        };

                private static final XrModuleProvider IMPL =
                        new XrModuleProvider() {
                            @Override
                            public XrSceneCoreSessionManager getXrSceneCoreSessionManager(
                                    android.app.Activity activity) {
                                return NO_OP_MANAGER;
                            }

                            @Override
                            public XrSceneCoreSessionInitializer getXrSceneCoreSessionInitializer(
                                    org.chromium.chrome.browser.lifecycle.ActivityLifecycleDispatcher
                                            dispatcher,
                                    XrSceneCoreSessionManager manager) {
                                return NO_OP_INITIALIZER;
                            }
                        };

                private XrModule() {}

                public static boolean isInstalled() {
                    return false;
                }

                public static XrModuleProvider getImpl() {
                    return IMPL;
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
