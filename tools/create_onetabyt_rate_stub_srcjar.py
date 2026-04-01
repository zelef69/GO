#!/usr/bin/env python3
"""Generate OneTabTube rate-dialog stub sources as a srcjar."""

import argparse
import textwrap
import zipfile


def _stub_sources():
    return {
        "org/chromium/chrome/browser/rate/BraveAskPlayStoreRatingDialog.java": textwrap.dedent(
            """\
            package org.chromium.chrome.browser.rate;

            import androidx.fragment.app.FragmentManager;

            public class BraveAskPlayStoreRatingDialog {
                public static final String TAG_FRAGMENT = "brave_ask_play_store_rating_dialog_tag";

                public static BraveAskPlayStoreRatingDialog newInstance(boolean isFromSettings) {
                    return new BraveAskPlayStoreRatingDialog();
                }

                public void show(FragmentManager manager, String tag) {}
            }
            """
        ),
        "org/chromium/chrome/browser/rate/BraveRateDialogFragment.java": textwrap.dedent(
            """\
            package org.chromium.chrome.browser.rate;

            import androidx.fragment.app.FragmentManager;

            public class BraveRateDialogFragment {
                public static final String TAG_FRAGMENT = "brave_rating_dialog_tag";

                public static BraveRateDialogFragment newInstance(boolean isFromSettings) {
                    return new BraveRateDialogFragment();
                }

                public void show(FragmentManager manager, String tag) {}
            }
            """
        ),
        "org/chromium/chrome/browser/rate/BraveRateThanksFeedbackDialog.java": textwrap.dedent(
            """\
            package org.chromium.chrome.browser.rate;

            import androidx.appcompat.app.AppCompatActivity;

            public class BraveRateThanksFeedbackDialog {
                public static final String TAG_FRAGMENT =
                        "brave_rate_thanks_feedback_dialog_tag";

                public static BraveRateThanksFeedbackDialog newInstance() {
                    return new BraveRateThanksFeedbackDialog();
                }

                public static void showBraveRateThanksFeedbackDialog(AppCompatActivity activity) {}
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
