#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt"

get_controls
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

# Deliberately not "ports/balatro": keeping a separate folder is what lets this
# port sit alongside the original one, with its own saves and its own copy of the
# purchased game file.
GAMEDIR="/$directory/ports/balatrolite"

export XDG_DATA_HOME="$GAMEDIR/saves"
export XDG_CONFIG_HOME="$GAMEDIR/saves"
export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"

mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"

## Uncomment the following line to log output for debugging.
# > "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Resolved before the cd below, which is what a relative $0 would be relative to.
LAUNCHER="$0"
case "$LAUNCHER" in
  /*) ;;
  *) LAUNCHER="$PWD/$LAUNCHER" ;;
esac

cd "$GAMEDIR" || exit 1

$ESUDO chmod a+x ./bin/*

GAMEFILE=""
if [ -f "Balatro.exe" ]; then
  GAMEFILE="Balatro.exe"
elif [ -f "balatro.exe" ]; then
  GAMEFILE="balatro.exe"
elif [ -f "Balatro.love" ]; then
  GAMEFILE="Balatro.love"
elif [ -f "balatro.love" ]; then
  GAMEFILE="balatro.love"
fi

# Set to 0 to keep the stock shaders. They are trimmed by default because both
# run over every pixel of every frame regardless of the settings that are meant
# to turn them off, which is the largest single cost on a handheld GPU.
TRIM_SHADERS=1

PERF_OPTIMIZATIONS=1
export BALATRO_PM_PERF_OPTIMIZATIONS="$PERF_OPTIMIZATIONS"

# Which physical button is A is decided by the handheld, not by the game. Some
# devices print the Xbox arrangement and some the Nintendo one, and the SDL
# mapping a device ships with does not always agree with its own case lettering,
# so the button under the player's thumb can report itself as another letter or
# as nothing at all. The first launch asks for each button by the letter printed
# beside it and keeps the answer in the saves folder. The game's options menu
# offers to ask again, which it does by removing that file; deleting it by hand
# or setting this to 1 has the same effect.
FORCE_BUTTON_SETUP=0
BUTTON_MAP_FILE="$GAMEDIR/saves/controller-map.txt"
# The game is told where the answer lives too: its options menu offers to ask
# again, which means removing this file for the next launch to act on.
export BALATRO_PM_BUTTON_MAP_FILE="$BUTTON_MAP_FILE"

# One patched build serves every device. The handheld layout reads the panel's
# real dimensions at startup, and the only device-specific behaviour left --
# which face button is which -- is passed in the environment at launch.
OUTPUT_GAME="Balatro_pm"

PATCHDIR="$GAMEDIR/patch-work"
WORKFILE="$GAMEDIR/.balatro-patching.${GAMEFILE##*.}"
SEVENZIP="$GAMEDIR/bin/7za.${DEVICE_ARCH}"

cleanup_patch_work() {
  # Only remove files created inside our known work directory.
  rm -f "$WORKFILE"
  rm -f "$PATCHDIR/globals.lua" "$PATCHDIR/main.lua" "$PATCHDIR/game.lua"
  rm -f "$PATCHDIR/cardarea.lua" "$PATCHDIR/engine/text.lua"
  rm -f "$PATCHDIR/portmaster/small_screen.lua"
  rm -f "$PATCHDIR/resources/fonts/m6x11plus.ttf"
  rm -f "$PATCHDIR/resources/shaders/CRT.fs"
  rm -f "$PATCHDIR/resources/shaders/background.fs"
  rmdir "$PATCHDIR/engine" "$PATCHDIR/portmaster" "$PATCHDIR/resources/fonts" \
    "$PATCHDIR/resources/shaders" "$PATCHDIR/resources" "$PATCHDIR" 2>/dev/null
}

build_patched_game() {
  mkdir -p "$PATCHDIR" || return 1
  cp "$GAMEFILE" "$WORKFILE" || return 1
  cd "$PATCHDIR" || return 1

  # Defaults for new profiles. The layout module also reapplies these after
  # saved desktop settings load, so an existing profile cannot restore CRT blur.
  "$SEVENZIP" x -aoa "$WORKFILE" globals.lua >/dev/null || return 1
  sed -i 's/crt = 70,/crt = 0,/g' globals.lua || return 1
  sed -i 's/bloom = 1/bloom = 0/g' globals.lua || return 1
  sed -i "s/shadows = 'On'/shadows = 'Off'/g" globals.lua || return 1
  sed -i 's/self.F_HIDE_BG = false/self.F_HIDE_BG = true/g' globals.lua || return 1
  "$SEVENZIP" u -aoa "$WORKFILE" globals.lua >/dev/null || return 1

  # Inject the responsive room and HUD, readable descriptions, and
  # screen-clamped controller tooltips.
  "$SEVENZIP" x -aoa "$WORKFILE" main.lua game.lua cardarea.lua engine/text.lua \
    >/dev/null || return 1
  mkdir -p portmaster || return 1
  cp "$GAMEDIR/patches/small_screen.lua" portmaster/small_screen.lua || return 1
  if ! grep -q 'portmaster/small_screen' main.lua; then
    sed -i '/require "challenges"/a require "portmaster/small_screen"' main.lua || return 1
  fi
  # Reduced motion used to multiply animation expressions by zero after their
  # sin/cos calls had already run. Guard the expensive terms themselves. These
  # counts intentionally pin the rewrite to the purchased 1.0.1o source: an
  # incompatible archive is left untouched instead of being partly patched.
  expect_occurrences() {
    local expected="$1" file="$2" needle="$3" actual
    actual=$(grep -F -o "$needle" "$file" | wc -l)
    if [ "$actual" -ne "$expected" ]; then
      echo "Patch mismatch in $file: expected $expected occurrences of $needle, found $actual."
      return 1
    fi
  }

  if [ "$PERF_OPTIMIZATIONS" -eq 1 ]; then
    # At zero CRT intensity the stock draw path still submits the completed
    # screen through a full-resolution fragment shader. Draw the Canvas
    # directly in that case; selecting any non-zero CRT setting restores the
    # original shader path. The replacement is pinned to one source match.
    expect_occurrences 1 game.lua "love.graphics.setShader( G.SHADERS['CRT'])" || return 1
    sed -i "s|love.graphics.setShader( G.SHADERS\['CRT'\])|if G.SETTINGS.GRAPHICS.crt > 0 then love.graphics.setShader( G.SHADERS['CRT']) else love.graphics.setShader() end|" game.lua || return 1
    expect_occurrences 1 game.lua "if G.SETTINGS.GRAPHICS.crt > 0 then love.graphics.setShader( G.SHADERS['CRT']) else love.graphics.setShader() end" || return 1

    expect_occurrences 11 cardarea.lua '(G.SETTINGS.reduced_motion and 0 or 1)*' || return 1
    sed -i \
      -e 's|(G.SETTINGS.reduced_motion and 0 or 1)\*0\.02\*math\.sin(2\*G\.TIMERS\.REAL+card\.T\.x)|(G.SETTINGS.reduced_motion and 0 or 0.02*math.sin(2*G.TIMERS.REAL+card.T.x))|g' \
      -e 's|(G.SETTINGS.reduced_motion and 0 or 1)\*0\.02\*math\.sin(2\*G\.TIMERS\.REAL+card\.T\.x+card\.T\.y)|(G.SETTINGS.reduced_motion and 0 or 0.02*math.sin(2*G.TIMERS.REAL+card.T.x+card.T.y))|g' \
      -e 's|(G.SETTINGS.reduced_motion and 0 or 1)\*0\.1\*math\.sin(0\.666\*G\.TIMERS\.REAL+card\.T\.x)|(G.SETTINGS.reduced_motion and 0 or 0.1*math.sin(0.666*G.TIMERS.REAL+card.T.x))|g' \
      -e 's|(G.SETTINGS.reduced_motion and 0 or 1)\*0\.03\*math\.sin(0\.666\*G\.TIMERS\.REAL+card\.T\.x)|(G.SETTINGS.reduced_motion and 0 or 0.03*math.sin(0.666*G.TIMERS.REAL+card.T.x))|g' \
      -e 's|(G.SETTINGS.reduced_motion and 0 or 1)\*0\.05\*math\.sin(2\*1\.666\*G\.TIMERS\.REAL+card\.T\.x)|(G.SETTINGS.reduced_motion and 0 or 0.05*math.sin(2*1.666*G.TIMERS.REAL+card.T.x))|g' \
      cardarea.lua || return 1
    expect_occurrences 0 cardarea.lua '(G.SETTINGS.reduced_motion and 0 or 1)*' || return 1
    expect_occurrences 11 cardarea.lua '(G.SETTINGS.reduced_motion and 0 or 0.' || return 1

    expect_occurrences 1 engine/text.lua 'if self.config.quiver then' || return 1
    expect_occurrences 1 engine/text.lua 'if self.config.rotate then letter.r =' || return 1
    expect_occurrences 1 engine/text.lua 'if self.config.float then letter.offset.y =' || return 1
    expect_occurrences 1 engine/text.lua 'if self.config.bump then letter.offset.y =' || return 1
    sed -i \
      -e 's|if self.config.quiver then|if self.config.quiver and not G.SETTINGS.reduced_motion then|' \
      -e 's|(G.SETTINGS.reduced_motion and 0 or 1)\*0\.02\*math\.sin(2\*G\.TIMERS\.REAL+k)|(G.SETTINGS.reduced_motion and 0 or 0.02*math.sin(2*G.TIMERS.REAL+k))|' \
      -e 's|if self.config.float then letter.offset.y = .*|if self.config.float then letter.offset.y = (G.SETTINGS.reduced_motion and 0 or math.sqrt(self.scale)*(2+(self.font.FONTSCALE/G.TILESIZE)*2000*math.sin(2.666*G.TIMERS.REAL+200*k))) + 60*(letter.scale-1) end|' \
      -e 's|if self.config.bump then letter.offset.y = .*|if self.config.bump then letter.offset.y = (G.SETTINGS.reduced_motion and 0 or self.bump_amount*math.sqrt(self.scale)*7*math.max(0, (5+self.bump_rate)*math.sin(self.bump_rate*G.TIMERS.REAL+200*k) - 3 - self.bump_rate)) end|' \
      engine/text.lua || return 1
    expect_occurrences 1 engine/text.lua 'if self.config.quiver and not G.SETTINGS.reduced_motion then' || return 1
    expect_occurrences 1 engine/text.lua '(G.SETTINGS.reduced_motion and 0 or 0.02*math.sin(2*G.TIMERS.REAL+k))' || return 1
    expect_occurrences 1 engine/text.lua 'if self.config.float then letter.offset.y = (G.SETTINGS.reduced_motion and 0 or math.sqrt' || return 1
    expect_occurrences 1 engine/text.lua 'if self.config.bump then letter.offset.y = (G.SETTINGS.reduced_motion and 0 or self.bump_amount' || return 1
  fi

  "$SEVENZIP" u -aoa "$WORKFILE" main.lua game.lua cardarea.lua engine/text.lua \
    portmaster/small_screen.lua >/dev/null || return 1

  if [ "$TRIM_SHADERS" -eq 1 ]; then
    "$SEVENZIP" x -aoa "$WORKFILE" resources/shaders/CRT.fs \
      resources/shaders/background.fs >/dev/null || return 1

    # Every frame the finished screen is drawn through CRT.fs, whether or not
    # the CRT effect is on. With it off the shader still evaluates six trig
    # calls of scanline pattern, a noise chain, and a chromatic aberration
    # branch for each of the ~786k pixels, then multiplies them all by zero.
    # Take the same result -- the bulge, the edge mask, and the contrast
    # correction, which are the parts that survive at zero intensity -- and
    # return it before any of that. The full path is untouched for anyone who
    # turns the effect back on.
    sed -i '/^vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc)/{n;s|^{|{ if (crt_intensity <= 0.000001 \&\& noise_fac <= 0.000001 \&\& glitch_intensity <= 0.000001) { MY_HIGHP_OR_MEDIUMP vec2 ftc = (tc*2.0 - vec2(1.0))*scale_fac; ftc += (ftc.yx*ftc.yx)*ftc*(distortion_fac - 1.0); MY_HIGHP_OR_MEDIUMP number fmask = (1.0 - smoothstep(1.0-feather_fac,1.0,abs(ftc.x) - BUFF))*(1.0 - smoothstep(1.0-feather_fac,1.0,abs(ftc.y) - BUFF)); ftc = (ftc + vec2(1.0))/2.0; MY_HIGHP_OR_MEDIUMP vec4 fcol = Texel(tex, ftc); fcol.rgb = (fcol.rgb - vec3(0.55))*1.14 + vec3(0.5); fcol.a = 1.0; return fcol*fmask; }|;}' \
      resources/shaders/CRT.fs || return 1
    grep -q 'crt_intensity <= 0.000001' resources/shaders/CRT.fs || return 1

    # The animated table underneath everything is a procedural paint pattern:
    # five iterations of five trig calls each, per pixel, per frame. Two
    # iterations keep the broad swirl and colours while dropping three fifths
    # of that loop work. Reduced motion also caches the settled result in Lua.
    if [ "$PERF_OPTIMIZATIONS" -eq 1 ]; then
      expect_occurrences 1 resources/shaders/background.fs 'i < 5; i++' || return 1
      sed -i 's/i < 5; i++/i < 2; i++/' resources/shaders/background.fs || return 1
      expect_occurrences 1 resources/shaders/background.fs 'i < 2; i++' || return 1
    fi

    "$SEVENZIP" u -aoa "$WORKFILE" resources/shaders/CRT.fs \
      resources/shaders/background.fs >/dev/null || return 1
  fi

  # Nunito is substantially clearer than the pixel font at handheld sizes.
  mkdir -p resources/fonts || return 1
  cp "$GAMEDIR/resources/fonts/Nunito-Black.ttf" resources/fonts/m6x11plus.ttf || return 1
  "$SEVENZIP" u -aoa "$WORKFILE" resources/fonts/m6x11plus.ttf >/dev/null || return 1

  # Test the complete archive before installing the generated output.
  "$SEVENZIP" t "$WORKFILE" >/dev/null || return 1
  "$SEVENZIP" l "$WORKFILE" | grep -q 'portmaster/small_screen.lua' || return 1

  cd "$GAMEDIR" || return 1
  mv -f "$WORKFILE" "$OUTPUT_GAME" || return 1
  return 0
}

# The build is made once and kept, so an updated port would otherwise keep
# launching the archive the previous version produced -- the layout, the options
# menu, and everything else patched in would silently stay at the old revision.
# Rebuild when anything that goes into it is newer than it is.
needs_build() {
  [ -z "$GAMEFILE" ] && return 1
  [ ! -f "$OUTPUT_GAME" ] && return 0
  for source in "$LAUNCHER" "$GAMEDIR/patches/small_screen.lua" \
                "$GAMEDIR/resources/fonts/Nunito-Black.ttf" "$GAMEDIR/$GAMEFILE"; do
    if [ -f "$source" ] && [ "$source" -nt "$OUTPUT_GAME" ]; then
      return 0
    fi
  done
  return 1
}

if needs_build; then
  echo "Preparing the ${OUTPUT_GAME} handheld build..."
  if build_patched_game; then
    echo "Handheld build ready."
    for stale in Balatro_4x3 Balatro_1x1; do
      [ -f "$stale" ] && echo "An older ${stale} build is still here and can be deleted."
    done
  else
    echo "Patch failed; no partial build was installed and the purchased game was not modified."
  fi
  cd "$GAMEDIR" || exit 1
  cleanup_patch_work
fi

DEVICE_PRINTS_SWAPPED_FACE_LABELS=0

if [ "${DEVICE_NAME}" = "TrimUI Smart Pro" ] || [ "${DEVICE_NAME}" = "TrimUI Brick" ]; then
  # TrimUI prints its face buttons in the physical AB/XY order. This is only the
  # guess used when the player has not answered the button setup; an answer
  # describes the device it was given on and always wins.
  DEVICE_PRINTS_SWAPPED_FACE_LABELS=1

  # The bundled versions of these libraries conflict with TrimUI's runtime.
  LIBDIR="$GAMEDIR/libs.${DEVICE_ARCH}"
  [ -f "$LIBDIR/libfontconfig.so.1" ] && $ESUDO rm -f "$LIBDIR/libfontconfig.so.1"
  [ -f "$LIBDIR/libtheoradec.so.1" ] && $ESUDO rm -f "$LIBDIR/libtheoradec.so.1"
fi

LAUNCH_GAME="$OUTPUT_GAME"

# Preserve the documented extensionless-file bypass when no source archive is
# present, so an unpatched build can still be provided by hand.
if [ ! -f "$LAUNCH_GAME" ] && [ -f "Balatro" ]; then
  LAUNCH_GAME="Balatro"
fi

if [ -f "$LAUNCH_GAME" ]; then
  pm_platform_helper "./bin/love.${DEVICE_ARCH}"

  # Both of these sit after the platform helper, so the questions are asked on
  # the display the game is about to use, under the same environment, and
  # nothing the helper sets up can overwrite the mapping afterwards. They sit
  # before gptokeyb because it is started to watch the game: the setup screen
  # brings its own ways out instead -- it gives up on its own if it is left
  # alone, and quits rather than stopping on an error.
  if [ "$FORCE_BUTTON_SETUP" -eq 1 ] || [ ! -f "$BUTTON_MAP_FILE" ]; then
    echo "Checking which button is which..."
    BALATRO_PM_BUTTON_FONT="$GAMEDIR/resources/fonts/Nunito-Black.ttf" \
      ./bin/love.${DEVICE_ARCH} ./buttonsetup
  fi

  # A run that ends without an answer -- skipped, timed out, or no controller
  # attached -- still leaves the file behind, holding comments and no mapping,
  # so the questions are asked once rather than on every launch.
  BUTTON_MAP=""
  if [ -f "$BUTTON_MAP_FILE" ]; then
    BUTTON_MAP=$(grep -v '^[[:space:]]*#' "$BUTTON_MAP_FILE" | grep -m 1 '[^[:space:]]')
  fi

  if [ -n "$BUTTON_MAP" ]; then
    # SDL reads this before anything opens the pad, and a mapping given here
    # outranks both the device's own database entry and the one LOVE bundles.
    # Balatro then sees the buttons under the names the player gave them, which
    # is also what its on-screen prompts are drawn from. Appended last: SDL
    # keeps the final mapping for a given controller.
    if [ -n "$SDL_GAMECONTROLLERCONFIG" ]; then
      export SDL_GAMECONTROLLERCONFIG="${SDL_GAMECONTROLLERCONFIG}
${BUTTON_MAP}"
    else
      export SDL_GAMECONTROLLERCONFIG="$BUTTON_MAP"
    fi
  elif [ "$DEVICE_PRINTS_SWAPPED_FACE_LABELS" -eq 1 ]; then
    export BALATRO_PM_SWAP_FACE_BUTTONS=1
  fi

  $GPTOKEYB "love.${DEVICE_ARCH}" &
  ./bin/love.${DEVICE_ARCH} "$LAUNCH_GAME"
else
  echo "Balatro game file not found. Copy Balatro.exe or Balatro.love into the balatro folder, then launch again."
fi

pm_finish
