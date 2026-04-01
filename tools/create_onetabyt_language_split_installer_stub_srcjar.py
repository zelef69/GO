#!/usr/bin/env python3
"""Generate a OneTabTube stub for LanguageSplitInstaller as a srcjar."""

import argparse
import textwrap
import zipfile


def _stub_sources():
    return {
        "org/chromium/chrome/browser/language/LanguageSplitInstaller.java": textwrap.dedent(
            """\
            package org.chromium.chrome.browser.language;

            import org.chromium.build.annotations.NullMarked;

            import java.util.Collections;
            import java.util.Set;

            @NullMarked
            public class LanguageSplitInstaller {
                private static final LanguageSplitInstaller INSTANCE = new LanguageSplitInstaller();

                public interface InstallListener {
                    void onComplete(boolean success);
                }

                public Set<String> getInstalledLanguages() {
                    return Collections.emptySet();
                }

                public boolean isLanguageSplitInstalled(String languageName) {
                    return AppLocaleUtils.isFollowSystemLanguage(languageName);
                }

                public void installLanguage(String languageName, InstallListener listener) {
                    if (listener != null) {
                        listener.onComplete(true);
                    }
                }

                public static LanguageSplitInstaller getInstance() {
                    return INSTANCE;
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
