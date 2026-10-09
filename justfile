# Run linter (check only)
lint:
    bundle exec standardrb

# Auto-fix linter warnings
fmt:
    bundle exec standardrb --fix

# Screenshot a command's output in a Rails app that loads this railbow
# checkout: one PNG of everything it prints, saved under tmp/shots/. The app
# comes from $RBW_APP, or the second argument. Needs freeze.
#   just shot "rails routes -g settings"
#   RBW_VERB=GET just shot "rails routes" ~/code/some_app
[doc("Screenshot a command in $RBW_APP as one PNG (tmp/shots/)")]
shot cmd app=env("RBW_APP", ""):
    #!/usr/bin/env bash
    set -euo pipefail
    cmd={{ quote(cmd) }}
    app={{ quote(app) }}
    app="${app/#\~/$HOME}"
    if [ -z "$app" ]; then
      echo "Set RBW_APP to a Rails app that loads this railbow checkout, or pass the app path as the second argument." >&2
      exit 1
    fi
    [ -d "$app" ] || { echo "No such directory: $app" >&2; exit 1; }
    # An app that loads railbow from a personal Gemfile.local usually selects it
    # with a directory hook in the interactive shell, and this script runs none.
    # Pick it up the same way, unless BUNDLE_GEMFILE is already set.
    if [ -z "${BUNDLE_GEMFILE:-}" ] && [ -f "$app/Gemfile.local" ]; then
      export BUNDLE_GEMFILE=Gemfile.local
    fi
    mkdir -p tmp/shots
    slug=$(printf %s "$cmd" | tr -cs '[:alnum:]' '-' | sed 's/^-//; s/-$//' | cut -c1-60)
    out="$PWD/tmp/shots/$(date +%Y%m%d-%H%M%S)-$slug.png"
    (cd "$app" && RBW_FORCE=1 freeze --execute "$cmd" --font.family "Menlo" -o "$out" >/dev/null)
    echo "$out"

# Record a command's output in a Rails app that loads this railbow checkout as
# a GIF: run on a terminal exactly cols wide, then scrolled from the top
# through all of it. Saved under tmp/shots/. The app comes from $RBW_APP, or
# the third argument. Needs vhs.
#   just cast "rails routes" 120
[doc("Record a command in $RBW_APP as a scrolling GIF at a set width (tmp/shots/)")]
cast cmd cols="120" app=env("RBW_APP", ""):
    #!/usr/bin/env bash
    set -euo pipefail
    cmd={{ quote(cmd) }}
    cols={{ quote(cols) }}
    app={{ quote(app) }}
    app="${app/#\~/$HOME}"
    if [ -z "$app" ]; then
      echo "Set RBW_APP to a Rails app that loads this railbow checkout, or pass the app path as the third argument." >&2
      exit 1
    fi
    [ -d "$app" ] || { echo "No such directory: $app" >&2; exit 1; }
    # An app that loads railbow from a personal Gemfile.local usually selects it
    # with a directory hook in the interactive shell, and this script runs none.
    # Pick it up the same way, unless BUNDLE_GEMFILE is already set.
    if [ -z "${BUNDLE_GEMFILE:-}" ] && [ -f "$app/Gemfile.local" ]; then
      export BUNDLE_GEMFILE=Gemfile.local
    fi
    mkdir -p tmp/shots
    slug=$(printf %s "$cmd" | tr -cs '[:alnum:]' '-' | sed 's/^-//; s/-$//' | cut -c1-60)
    out="$PWD/tmp/shots/$(date +%Y%m%d-%H%M%S)-$slug-${cols}c.gif"

    # A dry run on a pseudo-terminal of the same width counts the lines, so the
    # scroll ends where the output does. A pipe would not do: railbow lays out
    # for the terminal, and a piped run has none.
    lines=$(cd "$app" && RBW_FORCE=1 python3 -I -c '
    import os, pty, sys
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("bash", ["bash", "-c", "stty cols " + sys.argv[1] + "; " + sys.argv[2]])
    n = 0
    while True:
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        n += chunk.count(b"\n")
    os.waitpid(pid, 0)
    print(n)
    ' "$cols" "$cmd")

    # VHS sizes in pixels: Menlo 14 is about 9px a column and 17px a row, plus
    # padding. The window gets a little spare width and stty pins the exact
    # column count. 900px shows 53 rows; each step scrolls 45 of them.
    rows=53
    page=45
    steps=$(( lines > rows ? (lines - rows + page - 1) / page : 0 ))
    # A name of its own per run; vhs insists on the .tape extension.
    base=$(mktemp "$PWD/tmp/shots/.cast.XXXXXX")
    tape="$base.tape"
    trap 'rm -f "$base" "$tape"' EXIT
    {
      echo "Output \"$out\""
      echo 'Set Shell bash'
      echo 'Set FontFamily "Menlo"'
      echo 'Set FontSize 14'
      echo 'Set Padding 20'
      echo 'Set Framerate 10'
      echo "Set Width $(( cols * 9 + 100 ))"
      echo 'Set Height 900'
      echo 'Hide'
      echo "Type \`PS1='\$ '; stty cols $cols; clear\`"
      echo 'Enter'
      echo "Type \`RBW_FORCE=1 $cmd\`"
      echo 'Enter'
      echo 'Wait+Line@300s /^\$ ?$/'
      # Back to the top. VHS repeats a scroll one line at a time, so this is
      # exactly as far as needed, never a large catch-all number.
      echo "ScrollUp $(( lines + rows ))"
      echo 'Show'
      echo 'Sleep 1.5s'
      for _ in $(seq 1 "$steps"); do
        echo "ScrollDown $page"
        echo 'Sleep 700ms'
      done
      echo 'Sleep 1.5s'
    } > "$tape"
    (cd "$app" && vhs -q "$tape")
    echo "$out"
