# Screenshots and captures

Keep them out of git. One polish pass added about 12 MB of PNGs, and every
clone carries every one of them forever.

- **Where captures go.** Write captures to `.verification/` (the dev scenes'
  default) or to `docs/images/`. Both folders are git-ignored, so the files
  stay on the machine that made them.
- **How docs refer to a capture.** Docs name the capture and the scene that
  makes it, instead of embedding the image. Anyone who wants to see it re-runs
  the scene: for example, `godot --path . --resolution 1600x900
  res://dev/keeper_showcase.tscn -- .verification/keeper`.
- **Before and after shots for a review** go in the pull request's
  description or comments, not in a commit.
- **Art the game ships** lives under `assets/` and stays in git: icons,
  textures, sounds.

The screenshots from the October 4 polish passes were taken out of the repo on
2026-10-05; the copies on the owner's machine in `docs/images/` were kept.
Merging the `item-pictures` pull request with **Squash and merge** keeps them
out of `main`'s history entirely.
