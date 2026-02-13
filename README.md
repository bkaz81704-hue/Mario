# Mini Mario Prototype (LÖVE)

This is a small 2D platformer prototype inspired by Super Mario to demonstrate basic mechanics: movement, jumping, question (lucky) blocks, mushrooms, coins, simple enemies, and spikes.

Requirements
- Install LÖVE (love2d). On macOS you can install via Homebrew: `brew install --cask love` or download from https://love2d.org

Run
1. Open a terminal in this folder (the folder that contains `main.lua`).
2. Run:

```bash
love .
```

Controls
- Left / Right or A / D: move
- Z or Space: jump
- X or Left Shift: run
- R: restart

Adding the attached sprite and sounds
- Create a folder named `assets` in the project root.
- Save the image you attached as `assets/player.png`.
  - The game will automatically use `assets/player.png` if present; otherwise it falls back to a colored rectangle.
- Add sound files in `assets/` if you want audio:
  - `assets/music.ogg` — background music (will loop via crossfade for smoothness).
  - `assets/jump.wav` — jump SFX.
  - `assets/coin.wav` — coin / pickup SFX.
  - `assets/block.wav` — block hit SFX.

About copyrighted music (Super Mario theme)
- I cannot provide copyrighted audio or download it from YouTube on your behalf.
- If you already own a copy of the Super Mario theme (or another music file you have the rights to), place it in the project as `assets/music.ogg` and the game will play it automatically.

Converting your local audio/video file to OGG (if you already own it)
- Install ffmpeg on macOS via Homebrew: `brew install ffmpeg`.
- Example commands (run these only on files you already own):

```bash
# convert an MP3 to OGG (Vorbis)
ffmpeg -i "/path/to/your/music.mp3" -c:a libvorbis -q:a 5 assets/music.ogg

# extract & convert audio from a video file you own (e.g., MP4)
ffmpeg -i "/path/to/your/video.mp4" -vn -c:a libvorbis -q:a 5 assets/music.ogg
```

- After placing `assets/music.ogg` in the project, run the game with `love .` and it will play that music, looping it with a smooth crossfade.

Legal note
- Make sure you have the legal right to use the music (personal use vs. distribution). If you want a free alternative, I can add a CC0/CC-BY chiptune to the repo for you.

Development notes
- If you add artwork with different size/aspect, you may want to tweak the scaling in `main.lua` where `assets.player` is drawn.
- The physics and collisions are intentionally simple; you can replace them with a more robust collision library later.

If you want, I can:
- Add a permissively-licensed chiptune + SFX to the project so you have a longer background track without copyright issues.
- Tune jump parameters further (higher, snappier, or more floaty) — tell me the feel you want and I'll adjust values.
- Convert a provided audio file that you confirm you own (I can give exact ffmpeg command for that file type).
