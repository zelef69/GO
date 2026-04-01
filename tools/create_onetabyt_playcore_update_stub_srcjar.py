#!/usr/bin/env python3
"""Generate OneTabTube Play Core app-update stubs as a srcjar."""

import argparse
import textwrap
import zipfile


def _stub_sources():
    return {
        "com/google/android/play/core/install/InstallState.java": textwrap.dedent(
            """\
            package com.google.android.play.core.install;

            public class InstallState {
                public int installStatus() {
                    return com.google.android.play.core.install.model.InstallStatus.UNKNOWN;
                }
            }
            """
        ),
        "com/google/android/play/core/install/InstallStateUpdatedListener.java": textwrap.dedent(
            """\
            package com.google.android.play.core.install;

            public interface InstallStateUpdatedListener {
                void onStateUpdate(InstallState installState);
            }
            """
        ),
        "com/google/android/play/core/install/model/AppUpdateType.java": textwrap.dedent(
            """\
            package com.google.android.play.core.install.model;

            public final class AppUpdateType {
                public static final int FLEXIBLE = 0;
                public static final int IMMEDIATE = 1;

                private AppUpdateType() {}
            }
            """
        ),
        "com/google/android/play/core/install/model/InstallStatus.java": textwrap.dedent(
            """\
            package com.google.android.play.core.install.model;

            public final class InstallStatus {
                public static final int UNKNOWN = 0;
                public static final int DOWNLOADED = 11;

                private InstallStatus() {}
            }
            """
        ),
        "com/google/android/play/core/install/model/UpdateAvailability.java": textwrap.dedent(
            """\
            package com.google.android.play.core.install.model;

            public final class UpdateAvailability {
                public static final int UPDATE_NOT_AVAILABLE = 1;
                public static final int UPDATE_AVAILABLE = 2;

                private UpdateAvailability() {}
            }
            """
        ),
        "com/google/android/play/core/appupdate/AppUpdateInfo.java": textwrap.dedent(
            """\
            package com.google.android.play.core.appupdate;

            import com.google.android.play.core.install.model.InstallStatus;
            import com.google.android.play.core.install.model.UpdateAvailability;

            public class AppUpdateInfo {
                public int updateAvailability() {
                    return UpdateAvailability.UPDATE_NOT_AVAILABLE;
                }

                public int installStatus() {
                    return InstallStatus.UNKNOWN;
                }

                public int updatePriority() {
                    return 0;
                }

                public boolean isUpdateTypeAllowed(int appUpdateType) {
                    return false;
                }
            }
            """
        ),
        "com/google/android/play/core/appupdate/AppUpdateManager.java": textwrap.dedent(
            """\
            package com.google.android.play.core.appupdate;

            import android.app.Activity;
            import android.content.IntentSender;

            import com.google.android.gms.tasks.Task;
            import com.google.android.gms.tasks.Tasks;
            import com.google.android.play.core.install.InstallStateUpdatedListener;

            public class AppUpdateManager {
                public void registerListener(InstallStateUpdatedListener listener) {}

                public void unregisterListener(InstallStateUpdatedListener listener) {}

                public Task<AppUpdateInfo> getAppUpdateInfo() {
                    return Tasks.forResult(new AppUpdateInfo());
                }

                public Task<Void> completeUpdate() {
                    return Tasks.forResult(null);
                }

                public boolean startUpdateFlowForResult(
                        AppUpdateInfo appUpdateInfo,
                        int appUpdateType,
                        Activity activity,
                        int requestCode)
                        throws IntentSender.SendIntentException {
                    return false;
                }
            }
            """
        ),
        "com/google/android/play/core/appupdate/AppUpdateManagerFactory.java": textwrap.dedent(
            """\
            package com.google.android.play.core.appupdate;

            import android.content.Context;

            public final class AppUpdateManagerFactory {
                private AppUpdateManagerFactory() {}

                public static AppUpdateManager create(Context context) {
                    return new AppUpdateManager();
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
