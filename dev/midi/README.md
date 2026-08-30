# Development MIDI melodies

Small, single-track melody files for compiler/backend experiments: parse MIDI, split notes, schedule note-on/note-off events, or lower the same melody to a buzzer, speaker, radio/Wi-Fi experiment, screen event stream, or other target.

These are deliberately melody fixtures, not complete performances. Every file uses Standard MIDI type 0, 480 ticks per beat, one note at a time, and General MIDI program 80 (`Lead 1 (square)`) so ordinary playback has a simple chiptune-like voice.

## Files

- `beethoven-5-opening.mid` — Beethoven, Symphony No. 5, first-movement opening motto.
- `dvorak-new-world-largo.mid` — Dvořák, Symphony No. 9 *From the New World*, Largo theme; transposed to E major for a compact development fixture.
- `simple-gifts.mid` — the 1848 Shaker melody *Simple Gifts*. Copland later used this melody in *Appalachian Spring*; this file is the public-domain Shaker tune, not Copland's arrangement.

`manifest.json` records note counts, tempo, byte size, and SHA-256 so later transformations can leave explicit receipts.

## Copyright boundary

The Beethoven and Dvořák compositions and the *Simple Gifts* tune are public-domain material. These MIDI files are new, minimal encodings made for this repository rather than copies of modern performances or fan arrangements.

Do not vendor Copland, Tom Waits, game/chiptune, or other modern MIDI arrangements merely because a MIDI exists online. Add one when its source actually permits redistribution; otherwise keep it as an external reference.

## Public score / provenance references

- Beethoven Symphony No. 5: Mutopia Project, public-domain edition: https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=941
- Dvořák Symphony No. 9: Mutopia Project score source: https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=744
- *Simple Gifts*: Traditional Tune Archive/ABC notation derived from an 1848 Shaker manuscript: https://abcnotation.com/tunePage?a=tunearch.org%2Fwiki%2FSimple_Gifts.no-ext%2F0001
