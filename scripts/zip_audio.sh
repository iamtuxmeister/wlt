#!/usr/bin/env bash
# Zip priv/static/audio into old-testament.zip and new-testament.zip,
# grouped by book. Run from inside priv/static/audio.
set -euo pipefail

OLD_TESTAMENT=(
    genesis exodus leviticus numbers deuteronomy joshua judges ruth
    1st-samuel 2nd-samuel 1st-kings 2nd-kings 1st-chronicles 2nd-chronicles
    ezra nehemiah esther job psalms proverbs ecclesiastes song-of-solomon
    isaiah jeremiah lamentations ezekiel daniel hosea joel amos obadiah
    jonah micah nahum habakkuk zephaniah haggai zechariah malachi
)

NEW_TESTAMENT=(
    matthew mark luke john acts romans 1st-corinthians 2nd-corinthians
    galatians ephesians philippians colossians 1st-thessalonians
    2nd-thessalonians 1st-timothy 2nd-timothy titus philemon hebrews
    james 1st-peter 2nd-peter 1st-john 2nd-john 3rd-john jude revelation
)

OLD_ZIP="old-testament.zip"
NEW_ZIP="new-testament.zip"

rm -f "$OLD_ZIP" "$NEW_ZIP"

missing=0
for book in "${OLD_TESTAMENT[@]}"; do
    if [ -d "$book" ]; then
        zip -rq "$OLD_ZIP" "$book"
    else
        echo "warning: missing directory: $book" >&2
        missing=1
    fi
done

for book in "${NEW_TESTAMENT[@]}"; do
    if [ -d "$book" ]; then
        zip -rq "$NEW_ZIP" "$book"
    else
        echo "warning: missing directory: $book" >&2
        missing=1
    fi
done

echo "Wrote $OLD_ZIP ($(du -h "$OLD_ZIP" | cut -f1)) and $NEW_ZIP ($(du -h "$NEW_ZIP" | cut -f1))"
[ "$missing" -eq 0 ] || exit 1
