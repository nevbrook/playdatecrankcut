# Crank Cut

A video-editing game for the [Playdate](https://play.date). *Edit the cut. Land the hook. Go viral.*

You're a junior editor at a chaotic content studio. Use the crank as a jog wheel to scrub footage, then work through four passes on one clip:

1. **Hook** – pick the opening frame (live audience meter)
2. **Cuts** – mark cuts on the action
3. **Beat** – nudge cuts onto the beat
4. **Caption** – choose and time on-screen text

Publish to see views, watch-through and a **Viral Score**, plus a one-line verdict per factor. Career mode runs in weeks with follower targets; Sandbox has no deadline or scoring.

## Build & run

Requires the [Playdate SDK](https://play.date/dev/) (Lua).

```bash
pdc source CrankCut.pdx
open -a "Playdate Simulator" CrankCut.pdx
```

In the simulator, drag the on-screen crank to scrub. D-pad left/right steps one frame.

## Status

Prototype. All footage is procedural 1-bit drawing, so there are no assets. Not yet built: Daily Clip, Endless Feed, extra unlock tools, and a clip authoring tool.
