#!/usr/bin/env python3
"""Generate a OneTabTube stub for ModuleUtil as a srcjar."""

import argparse
import textwrap
import zipfile


def _stub_sources():
    return {
        "org/chromium/components/module_installer/util/ModuleUtil.java": textwrap.dedent(
            """\
            package org.chromium.components.module_installer.util;

            import org.chromium.build.annotations.NullMarked;

            @NullMarked
            public class ModuleUtil {
                public static void updateCrashKeys() {}

                public static void initApplication() {}

                public static void notifyModuleInstalled() {}
            }
            """
        ),
        "org/chromium/chrome/modules/on_demand/OnDemandModule.java": textwrap.dedent(
            """\
            package org.chromium.chrome.modules.on_demand;

            import org.chromium.build.annotations.NullMarked;

            @NullMarked
            public final class OnDemandModule {
                public static final String SPLIT_NAME = "on_demand";

                private OnDemandModule() {}
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
